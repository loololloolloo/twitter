# A member's contest of a ban or suspension, and an operator's decision on it.
# Deciding an appeal is not a second opinion on a report: it reverses (or
# confirms) a decision another operator already took, so the record has to know
# who took the original decision. That is why the sanctioning operator is its
# own column rather than something recovered from the audit trail later - the
# separation-of-duties rule is enforced against it while the decision is made.
class Appeal < ApplicationRecord
  belongs_to :user
  belongs_to :sanction_actor, class_name: "User", optional: true
  belongs_to :decided_by, class_name: "User", optional: true

  # The sanction being contested. Only the state that carries a reason is
  # contestable; a warning is notice, not a sanction, and is not appealed here.
  SANCTIONS = {
    "ban"        => "Ban",
    "suspension" => "Suspension"
  }.freeze

  STATES = %w[pending upheld reversed modified].freeze

  # The outcomes an operator may choose. "upheld" leaves the sanction in force,
  # "reversed" lifts it, and "modified" records a decision that changes the
  # sanction without lifting it.
  DECISIONS = {
    "upheld"   => "Upheld - the sanction stands",
    "reversed" => "Reversed - the sanction is lifted",
    "modified" => "Modified - the sanction is changed but stands"
  }.freeze

  MAX_BODY = 4_000

  validates :sanction_kind, inclusion: { in: SANCTIONS.keys }
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

  def sanction_label
    SANCTIONS.fetch(sanction_kind, sanction_kind.titleize)
  end

  def decision_label
    DECISIONS.fetch(state, state.titleize)
  end

  # True when this operator must not decide this appeal. The person who imposed
  # the sanction cannot judge its appeal, and nobody decides an appeal about
  # their own account. The rule lives here rather than in the controller so it
  # holds for every caller, including a console or a future API.
  def barred_for?(operator)
    return true if operator.nil?
    return true if user_id == operator.id
    return true if sanction_actor_id.present? && sanction_actor_id == operator.id

    false
  end

  # Why the operator is barred, phrased for the screen. The queue states this
  # next to the decision controls so a barred operator sees the reason instead
  # of a form that will refuse them.
  def bar_reason(operator)
    return "This appeal has already been decided." unless pending?
    return "You filed this appeal; it has to be decided by someone else." if user_id == operator.id
    if sanction_actor_id.present? && sanction_actor_id == operator.id
      return "You issued the #{sanction_label.downcase} this appeal contests."
    end

    nil
  end

  def decidable_by?(operator)
    pending? && !barred_for?(operator)
  end

  # Record a decision. Raises rather than returning false when the operator is
  # barred or the appeal is already closed, so a caller cannot accidentally
  # treat a refused decision as a recorded one.
  def decide!(decision:, actor:, note: "")
    raise ArgumentError, "unknown decision #{decision.inspect}" unless DECISIONS.key?(decision.to_s)
    raise ArgumentError, "appeal is already decided" unless pending?
    raise ArgumentError, "operator cannot decide this appeal" if barred_for?(actor)

    update!(
      state: decision.to_s,
      decided_by: actor,
      decision_note: note.to_s.strip,
      decided_at: Time.current
    )
  end

  # A reversal is not just a label on the appeal: it lifts the sanction the
  # member contested. Without this the queue would tell the member their ban was
  # lifted while the account stayed locked out. The lifting is recorded as a
  # `ModerationReversal`, so the account history reads "sanctioned, then
  # reversed" rather than the ban silently vanishing. Returns the reversal, or
  # nil when the sanction was already out of force and there is nothing to lift.
  def apply_reversal!(actor:)
    return nil unless state == "reversed" && sanction_in_effect?

    reversal = ModerationReversal.create!(
      user: user,
      actor: actor,
      imposed_by: sanction_actor,
      source: sanction_kind,
      source_id: 0,
      action: ModerationReversal::SOURCE_ACTIONS.fetch(sanction_kind),
      reason: "Appeal ##{id} reversed: #{decision_note.presence || 'no rationale recorded'}"
    )

    case sanction_kind
    when "ban"
      user.update!(is_banned: false, ban_reason: "", ban_permanent: false, ban_expires_at: nil)
    when "suspension"
      user.update!(is_suspended: false)
    end

    reversal
  end

  # Whether the contested sanction is still standing. A decision of "reversed"
  # against a ban an operator already lifted must not mint a second reversal.
  def sanction_in_effect?
    case sanction_kind
    when "ban"        then user.banned?
    when "suspension" then user.is_suspended?
    else false
    end
  end
end