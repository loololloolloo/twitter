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

  # Saved posts. Private to the account, so nothing but the owner's own list
  # ever reads them.
  has_many :bookmarks, dependent: :destroy
  has_many :bookmarked_tweets, through: :bookmarks, source: :tweet

  # Blocks. `blocking` is who this account has blocked; `blocked_by` is who has
  # blocked it. The two read different columns, so both directions exist.
  has_many :blocks, class_name: "Block", foreign_key: :blocker_id,
           dependent: :destroy, inverse_of: :blocker
  has_many :blocked_by, class_name: "Block", foreign_key: :blocked_id,
           dependent: :destroy, inverse_of: :blocked

  # Mutes are one-way and private, so only the muter's own list exists.
  has_many :mutes, class_name: "Mute", foreign_key: :muter_id,
           dependent: :destroy, inverse_of: :muter

  has_many :lists, dependent: :destroy
  has_many :list_memberships, dependent: :destroy

  has_many :user_warnings, dependent: :destroy

  # Internal notes about this account. They belong to the account record, not
  # the author, so deleting the account takes them and deleting the author does
  # not - `author_id` is left alone and the note reads back as "system".
  has_many :staff_notes, dependent: :destroy

  # Follow requests this account has made, and the ones waiting on it.
  has_many :sent_follow_requests, class_name: "FollowRequest", foreign_key: :requester_id,
           dependent: :destroy, inverse_of: :requester
  has_many :received_follow_requests, class_name: "FollowRequest", foreign_key: :target_id,
           dependent: :destroy, inverse_of: :target

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

  THEMES = %w[light dark].freeze

  def dark_theme?
    theme == "dark"
  end

  def theme=(value)
    super(THEMES.include?(value.to_s) ? value.to_s : "light")
  end

  # The whole-client designs an account can be put on, oldest last. These are
  # separate from THEMES: `design` is the shell and layout, `theme` is the
  # light/dark palette painted inside it, so a member can run the 2015 client
  # in dim mode.
  DESIGNS = %w[2019 2015 prototype].freeze

  # The design every account sees unless it has chosen otherwise.
  DEFAULT_DESIGN = "2019".freeze

  # The two recovered designs share a shell: a global top bar and a footer
  # instead of the 2019 left sidebar. Everything that switches on the shape of
  # the chrome asks this rather than naming the designs individually.
  LEGACY_DESIGNS = %w[2015 prototype].freeze

  def design=(value)
    super(DESIGNS.include?(value.to_s) ? value.to_s : DEFAULT_DESIGN)
  end

  def legacy_design?
    LEGACY_DESIGNS.include?(design)
  end

  # The population as visitors are allowed to see it: suspended accounts are
  # excluded. Directories use this so the "who to follow" lists never recommend
  # an account that cannot be opened.
  scope :visible, -> { not_suspended }

  # The operational flags the internal tool shows as tags. They do not remove an
  # account; they record how it should be treated, and the admin user page
  # renders them as the coloured chips the real tool uses.
  ACCOUNT_TAGS = {
    "search_blacklist" => "Search Blacklist",
    "trends_blacklist" => "Trends Blacklist",
    "do_not_amplify"   => "Do Not Amplify",
    "is_compromised"   => "Compromised",
    "is_high_profile"  => "High Profile",
    "requires_review"  => "Consult SIP-PES"
  }.freeze

  def account_tags
    ACCOUNT_TAGS.select { |column, _| public_send(column) }.values
  end

  # The running strike count: warnings that still count against the account.
  # Expired and revoked warnings stay in the table for the history but drop out
  # here, so the count answers "how much heat is on this account now" rather
  # than "how many times has it ever been warned".
  def strike_count
    user_warnings.active.count
  end

  # The rung the strike count has reached, or nil below the first warning.
  def strike_rung
    StrikeLadder.current(strike_count)
  end

  # The rung the next warning would reach, so the consequence is visible before
  # the operator issues it.
  def next_strike_rung
    StrikeLadder.next(strike_count)
  end

  # True when the account carries a tag that suppresses its reach. The public
  # timeline and search consult this, so the flags are not just decoration.
  def reach_limited?
    search_blacklist || trends_blacklist || do_not_amplify
  end

  scope :reach_limited, -> {
    where(search_blacklist: true).or(where(trends_blacklist: true)).or(where(do_not_amplify: true))
  }

  def pinned_tweet
    tweets.where.not(pinned_at: nil).order(pinned_at: :desc).first
  end

  # Accepts either a username or an email address so a member can sign in with
  # whichever they remember. Lookups are case-insensitive.
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

    user = find_by("username = ? COLLATE NOCASE OR email = ? COLLATE NOCASE", ident, ident)
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

  # Follower totals count every follow aimed at this account. Administrator-
  # granted bonus is added on top so the number shown on a profile matches every
  # other list in the app.
  def follower_count
    followers.count + bonus_followers.to_i
  end

  def following_count
    following.count
  end

  def tweet_count
    tweets.where(is_deleted: false).count
  end

  # Every like and favourite the account's posts have received, including any
  # administrator-granted padding on those posts. This is a total of what the
  # account's posts earned, not a count of the reactions the account itself
  # gave, which is what the profile's Likes figure reports.
  def likes_received_count
    tweets.sum(:bonus_likes) + tweets.sum(:bonus_favourites) +
      Like.joins(:tweet).where(tweets: { user_id: id })
          .where(tweets: { is_deleted: false }).count
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

  # ------------------------------------------------------- blocks and mutes
  # These answer the questions the timeline and profile ask before showing
  # anything about another account. They are all read-only and safe on a nil
  # viewer, so a signed-out page can ask them without a guard.

  def blocking?(other)
    return false if other.nil?

    blocks.exists?(blocked_id: other.id)
  end

  def blocked_by?(other)
    return false if other.nil?

    blocks_as_blocked = Block.where(blocker_id: other.id, blocked_id: id)
    blocks_as_blocked.exists?
  end

  # True when either direction of a block exists, which is the condition the
  # timeline and profile actually care about: a block hides both accounts from
  # each other regardless of who placed it.
  def blocked_with?(other)
    return false if other.nil? || other.id == id

    blocking?(other) || blocked_by?(other)
  end

  def muting?(other)
    return false if other.nil?

    mutes.exists?(muted_id: other.id)
  end

  # Creates the block and removes any follow in either direction, which is what
  # the client did: a block ends the relationship in both directions so neither
  # account is left following someone who can no longer see them.
  def block!(other)
    transaction do
      blocks.find_or_create_by!(blocked_id: other.id)
      Follow.where(follower_id: id, followee_id: other.id).delete_all
      Follow.where(follower_id: other.id, followee_id: id).delete_all
      FollowRequest.where(requester_id: id, target_id: other.id).delete_all
      FollowRequest.where(requester_id: other.id, target_id: id).delete_all
    end
  end

  def unblock!(other)
    blocks.where(blocked_id: other.id).delete_all
  end

  def mute!(other)
    mutes.find_or_create_by!(muted_id: other.id)
  end

  def unmute!(other)
    mutes.where(muted_id: other.id).delete_all
  end

  # The ids this account must not see, in either direction of a block. Used by
  # the timeline, search and suggestions so all three apply one rule instead of
  # each writing its own filter.
  def hidden_account_ids
    Block.where(blocker_id: id).or(Block.where(blocked_id: id))
         .pluck(:blocker_id, :blocked_id)
         .flatten
         .uniq - [ id ]
  end

  # Accounts this account has muted. Separate from blocks because a mute only
  # hides the muted account from the muter, never the other way round.
  def muted_account_ids
    mutes.pluck(:muted_id)
  end

  def follower_ids
    Follow.where(followee_id: id).pluck(:follower_id)
  end

  # Accounts that should not appear in this account's timelines: blocked either
  # way, or muted.
  def silenced_account_ids
    (hidden_account_ids + muted_account_ids).uniq
  end

  # ------------------------------------------------------ protected accounts

  def protected?
    protected
  end

  # Whether this account's posts may be read by the viewer. A public account is
  # readable by anyone; a protected one only by itself and its approved
  # followers, which is the rule the 2019 client enforced.
  def readable_by?(viewer)
    return true unless protected?
    return false if viewer.nil?
    return true if viewer.id == id

    Follow.exists?(follower_id: viewer.id, followee_id: id)
  end

  def pending_request_from?(account)
    return false if account.nil?

    received_follow_requests.pending.exists?(requester_id: account.id)
  end

  def requested_follow_of?(account)
    return false if account.nil?

    sent_follow_requests.pending.exists?(target_id: account.id)
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