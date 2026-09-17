class User < ApplicationRecord
  belongs_to :role

  has_many :tweets, dependent: :destroy
  has_many :likes, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :sessions, dependent: :destroy

  has_many :active_follows, class_name: "Follow", foreign_key: :follower_id,
                            dependent: :destroy, inverse_of: :follower
  has_many :passive_follows, class_name: "Follow", foreign_key: :followee_id,
                             dependent: :destroy, inverse_of: :followee
  has_many :following, through: :active_follows, source: :followee
  has_many :followers, through: :passive_follows, source: :follower

  has_many :tweet_views, dependent: :destroy
  has_many :profile_views, dependent: :destroy
  has_many :profile_viewers, class_name: "ProfileView", foreign_key: :viewer_id,
           dependent: :destroy, inverse_of: :viewer

  USERNAME_FORMAT = /\A[A-Za-z0-9_]{2,15}\z/

  validates :username, presence: true, format: { with: USERNAME_FORMAT },
                       uniqueness: { case_sensitive: false }
  validates :display_name, presence: true, length: { maximum: 50 }
  validates :email, presence: true, uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password_hash, presence: true
  validates :bio, length: { maximum: 160 }
  validates :bonus_followers, numericality: { greater_than_or_equal_to: 0 }

  scope :not_suspended, -> { where(is_suspended: false) }
  scope :humans, -> { where(is_bot: false) }
  scope :bots, -> { where(is_bot: true) }

  THEMES = %w[light dark].freeze

  def dark_theme?
    theme == "dark"
  end

  def theme=(value)
    super(THEMES.include?(value.to_s) ? value.to_s : "light")
  end

  # The population as visitors are allowed to see it: suspended accounts are
  # already excluded, and the simulated accounts drop out while the operator has
  # them hidden. Directories use this so hiding bots also empties the "who to
  # follow" lists, which would otherwise keep recommending invisible accounts.
  scope :visible, -> { SiteSetting.hide_bots? ? not_suspended.humans : not_suspended }

  # Decoded persona for a simulated account; empty for real members.
  def persona_hash
    @persona_hash ||= JSON.parse(persona.presence || "{}")
  rescue JSON::ParserError
    @persona_hash = {}
  end

  # Accepts either a username or an email address so a member can sign in with
  # whichever they remember. Lookups are case-insensitive.
  #
  # Simulated accounts are excluded: they exist to populate the timeline, not
  # to be signed into, and refusing them here means a bot can never be used as
  # a way into the admin panel.
  def email_domain
    email.to_s.split("@").last.to_s.downcase
  end

  # Free-mail domains are shown as "private" in the admin identity panel: mail
  # sent to them is controlled by an outside provider, not by this instance.
  PRIVATE_EMAIL_DOMAINS = %w[aol.com gmail.com gmx.com hotmail.com icloud.com
                             mail.com outlook.com proton.me yahoo.com].freeze

  def email_protected?
    PRIVATE_EMAIL_DOMAINS.include?(email_domain)
  end

  # A row whose address is missing or has no domain can never receive mail, so
  # it is treated as bounced.
  def email_bounced?
    address = email.to_s.strip
    address.blank? || !address.include?("@") || email_domain.blank?
  end

  # Inactivity is derived rather than stored: a suspended account, or one that
  # has not been seen for 90 days, reads as inactive in the panel.
  def email_inactive?
    return true if is_suspended?

    last_seen = last_login_at || created_at
    last_seen.present? && last_seen < 90.days.ago
  end

  def email_flags
    { "Bounced" => email_bounced?, "Inactive" => email_inactive?, "Protected" => email_protected? }
  end

  # The admin user list filters by the same three states the identity panel
  # shows, so the list and the panel cannot disagree about what "protected"
  # means. The conditions mirror the predicates above rather than restating a
  # second definition.
  scope :email_bounced, lambda {
    where("email IS NULL OR TRIM(email) = '' OR email NOT LIKE '%@%' OR email LIKE '%@'")
  }

  scope :email_protected, lambda {
    where("LOWER(SUBSTR(email, INSTR(email, '@') + 1)) IN (?)", PRIVATE_EMAIL_DOMAINS)
  }

  scope :email_inactive, lambda {
    where(is_suspended: true).or(where("COALESCE(last_login_at, created_at) < ?", 90.days.ago))
  }

  def self.authenticate(identifier, password)
    ident = identifier.to_s.strip
    return nil if ident.blank?

    user = humans.find_by("username = ? COLLATE NOCASE OR email = ? COLLATE NOCASE", ident, ident)
    return nil unless user&.password_matches?(password)

    user
  end

  def password_matches?(password)
    return false if password.blank?

    PasswordDigest.verify(password, password_hash)
  end

  def password=(plain)
    self.password_hash = PasswordDigest.hash(plain) if plain.present?
  end

  # Follower totals include any administrator-granted bonus so the number shown
  # on a profile matches every other list in the app.
  def follower_count
    followers.count + bonus_followers.to_i
  end

  def following_count
    following.count
  end

  def tweet_count
    tweets.where(is_deleted: false).count
  end

  def permission_keys
    role.permission_keys
  end

  def can?(key)
    permission_keys.include?(key.to_s)
  end

  def owner?
    role.name == Role::OWNER
  end

  # ---------------------------------------------------------------- bans
  # A timed ban that has run its course lifts itself the next time the account
  # is read, so an expired ban never needs an administrator to clear it.
  def resolve_ban!
    return false unless is_banned?
    return false if ban_permanent?
    return false if ban_expires_at.nil?

    if ban_expires_at <= Time.current
      update_columns(is_banned: false, ban_reason: "", ban_permanent: false,
                     ban_expires_at: nil, updated_at: Time.current)
      reload
      true
    else
      false
    end
  end

  def banned?
    resolve_ban!
    is_banned?
  end

  # A permanent ban is a different thing from a timed suspension: the account
  # is not coming back, so its profile is reduced to a notice rather than a
  # page of its own content.
  def permanently_banned?
    resolve_ban!
    is_banned? && ban_permanent?
  end

  def active?
    !is_banned? && !is_suspended?
  end
end