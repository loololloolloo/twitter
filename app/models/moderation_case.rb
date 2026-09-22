# One investigation: the account and/or post a set of reports are about, and
# the single decision that closes them all.
#
# The point of a case is that the reports it links stop being independent
# queue items. They already arrived separately and each already has its own
# resolution; the case is the layer above them that says "these are the same
# matter" and records one decision, so an operator reading the queue later
# sees one investigation rather than the same incident filed five times.
#
# A case is not a report. Resolving a report says what happened to that
# report; deciding a case says what happened to the matter, and is the only
# place a cluster gets a shared rationale.
class ModerationCase < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :tweet, optional: true
  belongs_to :opened_by, class_name: "User", optional: true
  belongs_to :decided_by, class_name: "User", optional: true

  # A case can be opened by an operator scanning the queue, by a report that
  # is promoted, or by the site itself when the same account is reported
  # repeatedly in a short window.
  ORIGINS = %w[operator report_promotion pattern].freeze

  # An investigation ends one of three ways. "actioned" means the decision is
  # recorded and enforcement followed (or is following); "dismissed" means the
  # operator read the cluster and found nothing to act on; "duplicate" means
  # this case turned out to be the same matter as another one.
  STATES = %w[open actioned dismissed duplicate].freeze

  DECISIONS = {
    "actioned"  => "Actioned - enforcement follows",
    "dismissed" => "Dismissed - no action taken",
    "duplicate" => "Duplicate - linked to another case"
  }.freeze

  MAX_TITLE = 200
  MAX_SUMMARY = 4_000
  MAX_NOTE = 2_000

  validates :title, presence: true, length: { maximum: MAX_TITLE }
  validates :state, inclusion: { in: STATES }
  validates :summary, length: { maximum: MAX_SUMMARY }

  scope :open,     -> { where(state: "open") }
  scope :decided,  -> { where.not(state: "open") }
  scope :recent,   -> { order(created_at: :desc, id: :desc) }

  def open?
    state == "open"
  end

  def decided?
    !open?
  end

  def decision_label
    DECISIONS.fetch(state, state.titleize)
  end

  # The subject of the case, phrased for a list row. A case can be about a
  # post alone, so neither the account nor the post is assumed to be present.
  def subject_label
    if user && tweet
      "post ##{tweet.id} by @#{user.username}"
    elsif user
      "@#{user.username}"
    elsif tweet
      "post ##{tweet.id}"
    else
      "no subject recorded"
    end
  end

  # The reports linked to this case, through the link rows so the link itself
  # (who attached the report and when) stays addressable.
  def case_links
    CaseLink.where(moderation_case_id: id)
  end

  def reports
    Report.where(id: case_links.select(:report_id))
  end

  def report_count
    case_links.count
  end

  # The reports that are still waiting. A case can be opened while its reports
  # are open; this is what tells the queue there is still work on it.
  def open_report_count
    reports.where(state: "open").count
  end

  # Why this operator must not decide this case. Nobody decides an
  # investigation they opened: the operator who assembled the cluster is the
  # one who already has a view of it, so the decision goes to a different
  # person. The rule lives here rather than in the controller so it holds for
  # every caller, including a console.
  def barred_for?(operator)
    return true if operator.nil?
    return true if opened_by_id.present? && opened_by_id == operator.id

    false
  end

  def bar_reason(operator)
    return "This case has already been decided." unless open?
    if opened_by_id.present? && opened_by_id == operator.id
      return "You opened this case; it has to be decided by someone else."
    end

    nil
  end

  def decidable_by?(operator)
    open? && !barred_for?(operator)
  end

  # Record the decision. Raises rather than returning false when the operator
  # opened the case, is nil, or the case is already closed, so a caller cannot
  # mistake a refusal for a recorded decision.
  def decide!(decision:, actor:, note: "")
    raise ArgumentError, "unknown decision #{decision.inspect}" unless DECISIONS.key?(decision.to_s)
    raise ArgumentError, "case is already decided" unless open?
    raise ArgumentError, "operator cannot decide this case" if barred_for?(actor)

    update!(
      state: decision.to_s,
      decided_by: actor,
      decision_note: note.to_s.strip,
      decided_at: Time.current
    )
  end
end
