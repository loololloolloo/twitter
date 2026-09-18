class Report < ApplicationRecord
  belongs_to :user
  belongs_to :reporter, class_name: "User", optional: true
  belongs_to :tweet, optional: true
  belongs_to :resolved_by, class_name: "User", optional: true

  CATEGORIES = {
    "abuse"       => "Abuse or harassment",
    "hate"        => "Hateful conduct",
    "spam"        => "Spam or platform manipulation",
    "impersonation" => "Impersonation",
    "private_info" => "Private information",
    "self_harm"   => "Self-harm or suicide",
    "other"       => "Something else"
  }.freeze

  STATES = %w[open actioned dismissed].freeze

  validates :category, inclusion: { in: CATEGORIES.keys }
  validates :state, inclusion: { in: STATES }

  scope :open,     -> { where(state: "open") }
  scope :resolved, -> { where.not(state: "open") }
  scope :recent,   -> { order(created_at: :desc, id: :desc) }

  def open?
    state == "open"
  end

  def resolved?
    !open?
  end

  def category_label
    CATEGORIES.fetch(category, category)
  end

  # An actioned report is one the operator agreed with; a dismissed one is a
  # report they looked at and decided needed no action. Both close the item.
  def resolve!(state:, actor:, note: "")
    update!(
      state: state,
      resolution_note: note.to_s,
      resolved_by: actor,
      resolved_at: Time.current
    )
  end
end
