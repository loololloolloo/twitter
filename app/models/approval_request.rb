require "json"

# A four-eyes approval request. The panel's highest-impact actions do not take
# effect when an operator picks them: they are filed here and applied only once
# a *different* operator approves. The separation is enforced in the model, not
# the screen, because a single insider with tool access is exactly the 2020
# failure mode this control exists to blunt.
#
# The three gated actions are the ones where one click is hardest to undo:
#
#   * permanent_ban  - a permanent ban removes an account's reach for good.
#   * email_change   - the registered email is the sign-in identifier and the
#                      address every account recovery flows through.
#   * handle_release - releasing a handle hands the name back to the pool, so
#                      anyone may claim it afterwards.
class ApprovalRequest < ApplicationRecord
  belongs_to :user
  belongs_to :requested_by, class_name: "User", optional: true
  belongs_to :decided_by, class_name: "User", optional: true

  # One gated action: the permission an operator needs to file it, the label
  # the queue shows, and a one-line statement of what approving it will do, so
  # the second operator reads the consequence rather than a bare action name.
  Action = Struct.new(:key, :label, :permission, :impact, keyword_init: true)

  ACTIONS = {
    "permanent_ban" => Action.new(
      key: "permanent_ban", label: "Permanent suspension", permission: "users.ban",
      impact: "Permanently ban the account. Its posts are hidden and the ban never expires."
    ),
    "email_change" => Action.new(
      key: "email_change", label: "Email change", permission: "users.email",
      impact: "Replace the account's registered email, which is its sign-in identifier."
    ),
    "handle_release" => Action.new(
      key: "handle_release", label: "Handle release", permission: "users.handle",
      impact: "Release the handle back to the pool and rename the account, so the old name may be claimed by anyone."
    )
  }.freeze

  STATES = %w[pending approved rejected].freeze
  DECISIONS = { "approved" => "Approve", "rejected" => "Reject" }.freeze

  validates :action_key, inclusion: { in: ACTIONS.keys }
  validates :state, inclusion: { in: STATES }
  validate :requester_recorded
  validate :single_pending_request

  scope :pending, -> { where(state: "pending") }
  scope :recent,  -> { order(created_at: :desc, id: :desc) }

  def pending?
    state == "pending"
  end

  def decided?
    !pending?
  end

  def action
    ACTIONS.fetch(action_key, nil)
  end

  def action_label
    action&.label || action_key
  end

  def impact
    action&.impact || ""
  end

  # The proposed change, decoded. A malformed payload reads as empty rather
  # than raising in a view, and the action's own validation refuses to apply it.
  def payload_data
    JSON.parse(payload.to_s.presence || "{}")
  rescue JSON::ParserError
    {}
  end

  def payload_data=(hash)
    self.payload = (hash || {}).to_json
  end

  def change_summary
    case action_key
    when "permanent_ban" then "permanently ban @#{user.username}"
    when "email_change" then "change @#{user.username} to #{payload_data['email']}"
    when "handle_release" then "release @#{user.username} as @#{payload_data['handle']}"
    else action_label.downcase
    end
  end

  # Nobody approves their own request. Named `barred_for?` to match the appeal
  # and case gates, so an operator excluded from one decision screen is
  # excluded the same way on the others.
  def barred_for?(operator)
    return true if operator.nil?
    return true if requested_by_id.present? && requested_by_id == operator.id

    false
  end

  def bar_reason(operator)
    return "This request has already been decided." unless pending?
    if requested_by_id.present? && requested_by_id == operator.id
      return "You filed this request; a second operator has to approve it."
    end

    nil
  end

  def decidable_by?(operator)
    pending? && !barred_for?(operator)
  end

  # Record the decision. Raises rather than returning false when the operator
  # filed the request or it is already closed, so a caller cannot mistake a
  # refusal for a recorded approval.
  def decide!(decision:, actor:, note: "")
    raise ArgumentError, "unknown decision #{decision.inspect}" unless DECISIONS.key?(decision.to_s)
    raise ArgumentError, "request is already decided" unless pending?
    raise ArgumentError, "the requester cannot decide their own request" if barred_for?(actor)

    update!(
      state: decision.to_s,
      decided_by: actor,
      decision_note: note.to_s.strip,
      decided_at: Time.current
    )
  end

  # Carry out the change the request describes. Only an approved request can be
  # applied, so a rejected one can never leak into the account.
  def apply!
    raise ArgumentError, "only an approved request can be applied" unless state == "approved"

    case action_key
    when "permanent_ban"
      user.update!(is_banned: true, ban_reason: payload_data["reason"].to_s,
                   ban_permanent: true, ban_expires_at: nil)
    when "email_change"
      user.update!(email: payload_data["email"].to_s)
    when "handle_release"
      raise ArgumentError, "the handle release is missing the new handle" if payload_data["handle"].blank?

      user.update!(username: payload_data["handle"].to_s)
    else
      raise ArgumentError, "unknown action #{action_key.inspect}"
    end
  end

  private

  def requester_recorded
    return if requested_by_id.present? || requested_by.present?

    errors.add(:requested_by, "must be recorded")
  end

  # One live request per action per account. Without this a second click files
  # a duplicate, and the queue would show two pending approvals for one change.
  def single_pending_request
    return unless pending?
    return if user_id.blank?

    duplicate = ApprovalRequest.where(user_id: user_id, action_key: action_key, state: "pending")
    duplicate = duplicate.where.not(id: id) if id
    errors.add(:base, "An approval for this action is already pending.") if duplicate.exists?
  end
end
