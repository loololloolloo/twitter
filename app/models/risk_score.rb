# A computed priority for the moderation queues. Reports arrives oldest-first
# because that is what the table gives you for free, but age is not risk: a
# week-old spam report and a week-old credible threat are not the same work, and
# an operator who works strictly in order spends their attention in the wrong
# place. This turns the signals the panel already holds into one comparable
# number so the queue can be worked highest-risk-first.
#
# The score is deliberately a sum of named factors rather than an opaque model.
# An operator is going to override the ordering when something looks wrong, and
# they can only do that responsibly if the screen tells them what drove the
# number. The factors are returned alongside the score for exactly that reason.
class RiskScore
  # The signals an active danger carries outweigh everything historical, so the
  # bands are named after what the operator should do, not after a percentile.
  BANDS = {
    "critical" => "Work now",
    "high"     => "Work soon",
    "medium"   => "Normal",
    "low"      => "Can wait"
  }.freeze

  BAND_ORDER = { "critical" => 0, "high" => 1, "medium" => 2, "low" => 3 }.freeze

  CAP = 100

  # Categories where a report is a danger signal in itself rather than a
  # housekeeping item. These are the same ones the verification and escalation
  # screens treat as cautionary.
  GRAVE_CATEGORIES = %w[self_harm private_info impersonation hate].freeze

  OPEN_REPORT_POINTS = 12
  GRAVE_CATEGORY_POINTS = 6
  ACTIONED_REPORT_POINTS = 4
  STRIKE_POINTS = 10
  NEW_ACCOUNT_DAYS = 7
  YOUNG_ACCOUNT_DAYS = 30
  NEW_ACCOUNT_POINTS = 15
  YOUNG_ACCOUNT_POINTS = 8
  BOUNCED_EMAIL_POINTS = 20
  NO_EMAIL_POINTS = 15

  Def = Struct.new(:label, :points, :detail, keyword_init: true)

  # Memoised per record so a queue that ranks its rows and then renders a chip
  # for each one pays for the calculation once, not twice.
  def self.for(record)
    record.instance_variable_get(:@risk_score) ||
      record.instance_variable_set(:@risk_score, new(record))
  end

  # Sort a collection of records highest-risk-first. The queue applies this
  # after its own limit so the ordering reflects the rows the operator would
  # actually see. The reports for every subject are loaded in one query so the
  # ranking does not turn a 200-row queue into 200 lookups.
  def self.rank(records)
    subjects = records.map { |record| subject_of(record) }.compact.uniq
    index = if subjects.empty?
              {}
            else
              Report.where(user_id: subjects.map(&:id)).group_by(&:user_id)
            end

    records.sort_by do |record|
      score = new(record, reports: index.fetch(subject_of(record)&.id, []))
      [ -score.score, record.respond_to?(:id) ? record.id : 0 ]
    end
  end

  def self.subject_of(record)
    record.is_a?(Report) ? record.user : record
  end

  def initialize(record, reports: nil)
    @record = record
    @reports = reports
  end

  attr_reader :record

  # The record a queue row is *about*. A report names a subject account; other
  # callers pass the account directly.
  def subject
    @subject ||= self.class.subject_of(record)
  end

  def score
    [ factors.sum(&:points), CAP ].min
  end

  def band
    case score
    when 70.. then "critical"
    when 45.. then "high"
    when 20.. then "medium"
    else "low"
    end
  end

  def band_label
    BANDS.fetch(band)
  end

  def band_rank
    BAND_ORDER.fetch(band)
  end

  # Every factor that contributed points, most significant first. A factor worth
  # zero is dropped rather than shown as "0 points", so the operator reads only
  # what actually moved the number.
  def factors
    @factors ||= raw_factors.reject { |factor| factor.points.zero? }
                 .sort_by { |factor| -factor.points }
  end

  # A one-line justification for the score, used as the title on the queue
  # chip so the ordering is never unexplained.
  def explanation
    return "No risk signals on this account." if factors.empty?

    factors.map { |factor| "#{factor.label} (#{factor.detail}, +#{factor.points})" }.join("; ")
  end

  private

  def raw_factors
    user = subject
    return [] if user.nil?

    [
      Def.new(label: "Open reports", points: open_report_points, detail: "#{open_reports.size} open"),
      Def.new(label: "Grave category", points: grave_category_points,
              detail: "#{grave_categories.size} high-severity"),
      Def.new(label: "Actioned reports", points: actioned_reports.size * ACTIONED_REPORT_POINTS,
              detail: "#{actioned_reports.size} upheld"),
      Def.new(label: "Active strikes", points: user.strike_count * STRIKE_POINTS,
              detail: "#{user.strike_count}"),
      Def.new(label: "Account state", points: state_points, detail: state_detail),
      Def.new(label: "Escalation tag", points: user.requires_review ? 15 : 0, detail: "consult SIP-PES"),
      Def.new(label: "Reach limited", points: user.reach_limited? ? 10 : 0, detail: "blacklisted"),
      Def.new(label: "Account age", points: age_points, detail: age_detail),
      Def.new(label: "Email unusable", points: email_points, detail: email_detail)
    ]
  end

  def open_reports
    @open_reports ||= reports.select { |report| report.state == "open" }
  end

  def actioned_reports
    @actioned_reports ||= reports.select { |report| report.state == "actioned" }
  end

  def grave_categories
    @grave_categories ||= open_reports.select { |report| GRAVE_CATEGORIES.include?(report.category) }
  end

  def reports
    @reports ||= Report.where(user_id: subject.id).to_a
  end

  def open_report_points
    open_reports.size * OPEN_REPORT_POINTS
  end

  def grave_category_points
    grave_categories.size * GRAVE_CATEGORY_POINTS
  end

  def state_points
    user = subject
    return 60 if user.is_banned && user.ban_permanent
    return 40 if user.is_banned
    return 25 if user.is_suspended
    return 20 if user.is_compromised

    0
  end

  def state_detail
    user = subject
    return "permanently banned" if user.is_banned && user.ban_permanent
    return "banned" if user.is_banned
    return "suspended" if user.is_suspended
    return "compromised" if user.is_compromised

    "active"
  end

  def age_days
    return nil if subject.created_at.nil?

    ((Time.current - subject.created_at) / 1.day).floor
  end

  def age_points
    days = age_days
    return 0 if days.nil?
    return NEW_ACCOUNT_POINTS if days < NEW_ACCOUNT_DAYS
    return YOUNG_ACCOUNT_POINTS if days < YOUNG_ACCOUNT_DAYS

    0
  end

  def age_detail
    days = age_days
    days.nil? ? "unknown" : "#{days}d old"
  end

  def email_points
    return NO_EMAIL_POINTS if subject.email_bounced?
    return 5 if subject.email_protected?

    0
  end

  def email_detail
    return "bounces" if subject.email_bounced?
    return "private domain" if subject.email_protected?

    "usable"
  end
end
