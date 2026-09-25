# A single action applied to many selected accounts at once.
#
# Bulk moderation is the highest-blast-radius control in the panel: one click
# can suspend a whole slice of the population, and it cannot be taken back by
# looking at a row again. Two things follow from that and are enforced here
# rather than left to the screen.
#
#   * Eligibility is per account and is the panel's ordinary rules, applied to
#     each row: nobody may act on themselves, on the owner, or on an account at
#     or above their own rank. A selection that passes the form can still hold
#     rows the operator is not allowed to touch, so the plan reports them as
#     skipped instead of silently acting on them.
#   * The plan is computed before anything is written, so the confirmation
#     screen can state the exact number that will change and who is left out.
#
# Accounts tagged for escalation are held back from enforcement actions. The
# tag means "consult before acting", and a bulk run is exactly where that
# instruction gets lost, so the run leaves them alone and says so.
module BulkUserAction
  Action = Struct.new(:key, :label, :permission, :tone, :active_verb, :past_verb,
                      :destructive, keyword_init: true)

  # The actions the accounts list offers. Each one carries its own permission
  # so a run cannot borrow the grant of a different action.
  ACTIONS = {
    "suspend"   => Action.new(key: "suspend", label: "Suspend", permission: "users.suspend",
                              tone: "danger", active_verb: "suspend", past_verb: "suspended",
                              destructive: false),
    "reinstate" => Action.new(key: "reinstate", label: "Reinstate", permission: "users.suspend",
                              tone: "primary", active_verb: "reinstate", past_verb: "reinstated",
                              destructive: false),
    "ban"       => Action.new(key: "ban", label: "Ban permanently", permission: "users.ban",
                              tone: "danger", active_verb: "ban", past_verb: "banned",
                              destructive: false),
    "unban"     => Action.new(key: "unban", label: "Lift ban", permission: "users.ban",
                              tone: "primary", active_verb: "unban", past_verb: "unbanned",
                              destructive: false),
    "verify"    => Action.new(key: "verify", label: "Grant verified badge", permission: "users.verify",
                              tone: "primary", active_verb: "verify", past_verb: "verified",
                              destructive: false),
    "unverify"  => Action.new(key: "unverify", label: "Revoke verified badge", permission: "users.verify",
                              tone: "primary", active_verb: "unverify", past_verb: "unverified",
                              destructive: false),
    "tag_on"    => Action.new(key: "tag_on", label: "Apply tag", permission: "users.tags",
                              tone: "primary", active_verb: "tag", past_verb: "tagged",
                              destructive: false),
    "tag_off"   => Action.new(key: "tag_off", label: "Clear tag", permission: "users.tags",
                              tone: "primary", active_verb: "untag", past_verb: "untagged",
                              destructive: false),
    "delete"    => Action.new(key: "delete", label: "Delete accounts", permission: "users.delete",
                              tone: "danger", active_verb: "delete", past_verb: "deleted",
                              destructive: true)
  }.freeze

  # Enforcement actions are the ones the escalation tag protects. Restorative
  # actions and cosmetic changes are not held back, or an account could never
  # be released from a limit by bulk work.
  ENFORCEMENT = %w[suspend ban delete].freeze

  # Actions that make no sense turned on the operator's own account.
  SELF_BLOCKED = %w[suspend reinstate ban unban delete].freeze

  # The reason is what makes a run readable afterwards, so it is mandatory
  # where the action removes an account or its standing. Restorative actions do
  # not demand one. Lives here rather than in the controller because the
  # confirmation screen labels the field with the same rule.
  REASON_REQUIRED = (ENFORCEMENT + %w[tag_on]).freeze

  # The reason for skipping a selected account, in the operator's words. The
  # order here is the order the reasons are listed on the confirmation screen.
  # Each reads after a "N selected accounts:" prefix, so the line is grammatical
  # at one account and at many.
  SKIP_REASONS = {
    "self"      => "your own account",
    "owner"     => "the owner account, which answers to nobody",
    "rank"      => "at or above your own level",
    "escalated" => "tagged for escalation (consult SIP-PES before acting)"
  }.freeze

  # The outcome of reading a selection against one action: the accounts that
  # will change, and a tally of why the rest were left alone. Computing this
  # never writes, so the screen can show it and the operator can back out.
  Result = Struct.new(:action, :tag, :eligible, :skipped, keyword_init: true) do
    def total
      eligible.size + skipped.values.sum
    end

    def eligible_ids
      eligible.map(&:id)
    end

    def skip_lines
      skipped.filter_map { |reason, count| "#{count} selected account#{"s" if count != 1}: #{SKIP_REASONS.fetch(reason, reason)}" if count.positive? }
    end

    # "37 accounts" - the blast radius as a phrase, so no caller prints a bare
    # number that could be mistaken for something else.
    def account_phrase
      "#{eligible.size} account#{'s' if eligible.size != 1}"
    end

    # The one-line description of the change, used on the button and in the
    # audit detail.
    def summary
      case action.key
      when "tag_on", "tag_off" then tag ? "#{action.active_verb} #{tag_label}" : action.active_verb
      else action.active_verb
      end
    end

    def tag_label
      User::ACCOUNT_TAGS[tag]
    end
  end

  # Reads a selection against an action without writing anything. `tag` is only
  # consulted for the tag actions; an unknown tag makes the result empty rather
  # than raising, because the caller validates it first.
  def self.plan(action_key, users, actor, tag: nil)
    action = ACTIONS.fetch(action_key)
    eligible = []
    skipped = Hash.new(0)

    users.each do |user|
      reason = refusal(user, action, actor)
      if reason
        skipped[reason] += 1
      else
        eligible << user
      end
    end

    Result.new(action: action, tag: tag, eligible: eligible, skipped: skipped)
  end

  # The reason a single account is out of scope, or nil when it may be acted
  # on. This mirrors the per-account guards in Admin::UsersController, so a
  # bulk run can never reach a row the single-account screen would refuse.
  def self.refusal(user, action, actor)
    return "self" if SELF_BLOCKED.include?(action.key) && user.id == actor.id
    return "owner" if user.owner? && user.id != actor.id
    return "rank" unless actor.role.rank > user.role.rank
    return "escalated" if ENFORCEMENT.include?(action.key) && user.requires_review

    nil
  end

  # Carries out the planned action on every eligible account. One transaction
  # so a failure part-way leaves the population untouched rather than half
  # suspended, and one audit entry per account so each affected record keeps
  # its own trail next to the single-account actions it sits beside.
  def self.apply(result, actor, reason: "")
    applied = []

    ActiveRecord::Base.transaction do
      result.eligible.each do |user|
        perform(result, user, actor, reason)
        applied << user
      end
    end

    applied
  end

  def self.perform(result, user, actor, reason)
    detail = result.summary
    detail += ": #{reason}" if reason.present?

    case result.action.key
    when "suspend"
      user.update!(is_suspended: true)
      user.sessions.destroy_all
    when "reinstate"
      user.update!(is_suspended: false)
    when "ban"
      user.update!(is_banned: true, ban_reason: reason, ban_permanent: true, ban_expires_at: nil)
    when "unban"
      user.update!(is_banned: false, ban_reason: "", ban_permanent: false, ban_expires_at: nil)
    when "verify"
      user.update!(is_verified: true)
    when "unverify"
      user.update!(is_verified: false)
    when "tag_on"
      user.update!(result.tag => true, tag_note: reason.presence || user.tag_note)
      user.update!(review_reason: reason) if result.tag == User::ELEVATED_TAG && reason.present?
    when "tag_off"
      user.update!(result.tag => false, tag_note: reason.presence || user.tag_note)
      user.update!(review_reason: "") if result.tag == User::ELEVATED_TAG
    when "delete"
      user.destroy!
    end

    AuditLog.record(actor: actor, action: "users.#{audit_key(result)}",
                    target: "user:#{user.id}", detail: detail)
  end

  # The audit action key for a bulk run. Each maps to the same key the
  # single-account control writes, so filtering the trail by action returns
  # both the one-at-a-time change and the bulk one.
  def self.audit_key(result)
    case result.action.key
    when "suspend", "reinstate" then "suspend"
    when "ban", "unban"         then "ban"
    when "verify", "unverify"   then "verify"
    when "tag_on", "tag_off"    then "tags"
    else result.action.key
    end
  end

  # Every action the operator is allowed to run, for the picker on the list.
  def self.allowed_for(actor)
    ACTIONS.values.select { |action| actor.can?(action.permission) }
  end

  def self.fetch(key)
    ACTIONS[key.to_s]
  end

  def self.tag?(key)
    %w[tag_on tag_off].include?(key.to_s)
  end
end
