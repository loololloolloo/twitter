# A member's request for the verified badge, and the operator's decision on it.
# The request is the only way the badge is granted: approving writes
# `is_verified` on the account, so a badge in the wild always has a request
# behind it naming the operator who approved it. That is the difference from the
# bare toggle on the account page, which is for correcting a mistake.
class VerificationRequest < ApplicationRecord
  belongs_to :user
  belongs_to :reviewed_by, class_name: "User", optional: true

  # What the account is asking to be verified as. The list is the one the real
  # badge covered: a notable person or brand, not a private individual.
  CATEGORIES = {
    "individual" => "Notable individual",
    "business"   => "Business or brand",
    "government" => "Government or public body",
    "journalist" => "Journalist or news outlet",
    "other"      => "Something else"
  }.freeze

  STATES = %w[pending approved denied].freeze

  DECISIONS = {
    "approved" => "Approve - grant the verified badge",
    "denied"   => "Deny - do not grant the badge"
  }.freeze

  MAX_BODY = 2_000
  MAX_REASON = 500

  validates :category, inclusion: { in: CATEGORIES.keys }
  validates :state, inclusion: { in: STATES }
  validates :body, presence: true, length: { maximum: MAX_BODY }

  scope :pending, -> { where(state: "pending") }
  scope :decided, -> { where.not(state: "pending") }
  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def pending?
    state == "pending"
  end

  def decided?
    !pending?
  end

  def category_label
    CATEGORIES.fetch(category, category.titleize)
  end

  def decision_label
    case state
    when "approved" then "Approved - badge granted"
    when "denied"   then "Denied - badge not granted"
    else "Pending"
    end
  end

  # Why this operator must not decide this request. Nobody reviews their own
  # application: approving it would grant themselves the badge and record them
  # as their own reviewer. The rule lives in the model so it holds for every
  # caller, not only the controller.
  def barred_for?(operator)
    return true if operator.nil?
    return true if user_id == operator.id

    false
  end

  def bar_reason(operator)
    return "This request has already been decided." unless pending?
    return "You filed this request; it has to be reviewed by someone else." if user_id == operator.id

    nil
  end

  def decidable_by?(operator)
    pending? && !barred_for?(operator)
  end

  # Record a decision. Approving grants the badge in the same step, so the two
  # can never disagree; a denial requires a reason because the member is told
  # the outcome and "no" with no explanation is not a decision they can act on.
  # Raises rather than returning false, so a caller cannot mistake a refused
  # decision for a recorded one.
  def decide!(decision:, actor:, note: "")
    decision = decision.to_s
    raise ArgumentError, "unknown decision #{decision.inspect}" unless DECISIONS.key?(decision)
    raise ArgumentError, "request is already decided" unless pending?
    raise ArgumentError, "operator cannot decide this request" if barred_for?(actor)

    note = note.to_s.strip
    raise ArgumentError, "a reason is required to deny a request" if decision == "denied" && note.blank?

    transaction do
      update!(
        state: decision,
        reviewed_by: actor,
        decision_note: note.first(MAX_REASON),
        decided_at: Time.current
      )

      user.update!(is_verified: true) if decision == "approved"
    end
  end
end
