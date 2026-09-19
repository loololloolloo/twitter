# A formal warning issued to an account by an operator. Unlike a ban or a
# suspension it changes nothing about what the account can do; it records that
# someone was told, why, and by whom, so the next operator sees the history
# rather than only the current state.
class UserWarning < ApplicationRecord
  belongs_to :user
  belongs_to :actor, class_name: "User", optional: true

  # The categories the warning form offers. They are the ones a reviewer
  # actually reaches for; "other" exists so a warning is never blocked on
  # choosing one.
  CATEGORIES = {
    "spam"           => "Spam or platform manipulation",
    "abuse"          => "Abusive behaviour",
    "harassment"     => "Harassment",
    "hateful"        => "Hateful conduct",
    "misinformation" => "Misleading information",
    "impersonation"  => "Impersonation",
    "other"          => "Other"
  }.freeze

  validates :category, inclusion: { in: CATEGORIES.keys }

  scope :recent, -> { order(created_at: :desc, id: :desc) }
  scope :active, -> { where(expires_at: nil).or(where("expires_at > ?", Time.current)) }

  def category_label
    CATEGORIES.fetch(category, category.titleize)
  end

  # A warning with no expiry stands until it is superseded; one with an expiry
  # only counts against the account while it is in the future.
  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def active?
    !expired?
  end
end
