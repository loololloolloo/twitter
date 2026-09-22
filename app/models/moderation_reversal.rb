# One reversal of a moderation action. The action it undoes is still in the
# database, unmodified; this row is what makes the history show both the
# sanction and the decision to lift it.
#
# A reversal is not a delete. Expiring a warning or clearing a ban leaves the
# original rows exactly as they were, so the account's record reads as
# "sanctioned, then reversed" rather than pretending the sanction never
# happened. Leaving the trail intact is the point.
class ModerationReversal < ApplicationRecord
  belongs_to :user
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :imposed_by, class_name: "User", optional: true

  # What kind of sanction was reversed. This is the vocabulary the history and
  # the audit trail share, so it is spelled out rather than inferred.
  SOURCES = {
    "ban"        => "Ban",
    "suspension" => "Suspension",
    "warning"    => "Warning"
  }.freeze

  # The audit action a reversal is recorded under. Every caller writes this,
  # so centralising it keeps the trail greppable by one name.
  AUDIT_ACTION = "users.reverse".freeze

  # The action key the *original* sanction was recorded under. The reversal
  # history sits beside that entry, so it needs to know which key it undoes.
  SOURCE_ACTIONS = {
    "ban"        => "users.ban",
    "suspension" => "users.suspend",
    "warning"    => "users.warn"
  }.freeze

  validates :source, inclusion: { in: SOURCES.keys }
  validates :reason, presence: true
  validate :reverser_differs_from_imposer

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def source_label
    SOURCES.fetch(source, source)
  end

  def summary
    "Reversed #{source_label.downcase}"
  end

  # Nobody undoes a sanction they imposed themselves. This mirrors the appeal
  # and approval gates: the operator who decided a matter does not get to be
  # the one who reconsiders it. Reversing a colleague's ban is as much a
  # judgement call as placing it, so the control applies in both directions.
  #
  # Class-level because the screen has to ask "would this operator be refused?"
  # before the reversal row exists, and the same answer has to come from the
  # action path. One method, so the display and the guard cannot drift.
  def self.bar_reason(imposed_by, operator, source)
    return "You cannot reverse a sanction on your own account." if operator.nil?
    return nil if imposed_by.nil? || imposed_by.id != operator.id

    "You imposed this #{SOURCES.fetch(source, source).downcase}; " \
      "a different operator has to reverse it."
  end

  def self.reversible_by?(imposed_by, operator, source)
    bar_reason(imposed_by, operator, source).nil?
  end

  def bar_reason(operator)
    self.class.bar_reason(imposed_by, operator, source)
  end

  def reversible_by?(operator)
    self.class.reversible_by?(imposed_by, operator, source)
  end

  private

  # The rule lives in the model, not only in the screen, so a caller cannot
  # bypass it by building the row directly.
  def reverser_differs_from_imposer
    return if actor_id.blank? || imposed_by_id.blank?
    return unless actor_id == imposed_by_id

    errors.add(:actor, "cannot reverse a sanction they imposed")
  end
end
