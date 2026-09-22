require "test_helper"

# Covers the appeals queue and its separation-of-duties rule. An appeal is a
# second look at a ban another operator imposed, so the operator who imposed
# the sanction may not decide the appeal. These tests check the queue reads
# correctly, that the barred operator is told why instead of being shown a form
# that refuses, and that only a different, permitted operator can record a
# decision.
class AdminAppealsTest < ActionDispatch::IntegrationTest
  # A filed appeal against a ban that `sanction_actor` imposed. `member` is the
  # account contesting the ban.
  def filed_appeal(member:, sanction_actor:, state: "pending", **attrs)
    Appeal.create!(
      user: member,
      sanction_kind: "ban",
      sanction_reason: "Repeated spam",
      sanction_actor: sanction_actor,
      body: "The links were not mine.",
      state: state,
      **attrs
    )
  end

  test "the owner sees the pending appeals queue with the sanctioning operator" do
    owner = create_user(username: "king", role: "owner")
    other = create_user(username: "other", role: "owner")
    member = create_user(username: "member")
    filed_appeal(member: member, sanction_actor: other)

    sign_in(owner)
    get admin_appeals_path

    assert_response :success
    assert_match(/Appeals/, response.body)
    assert_match(/@member/, response.body)
    assert_match(/issued by <strong>@other<\/strong>/, response.body)
    assert_match(/The links were not mine\./, response.body)
  end

  test "the operator who issued the sanction is barred and told why" do
    issuer = create_user(username: "issuer", role: "owner")
    member = create_user(username: "member")
    filed_appeal(member: member, sanction_actor: issuer)

    sign_in(issuer)
    get admin_appeals_path

    assert_response :success
    # The screen states the bar rather than hiding the controls silently.
    assert_match(/You cannot decide this appeal/, response.body)
    assert_match(/You issued the ban this appeal contests\./, response.body)
    # No decision form is rendered for a barred operator.
    assert_no_match(/Record decision/, response.body)
  end

  test "a barred operator cannot decide through a direct request" do
    issuer = create_user(username: "issuer", role: "owner")
    member = create_user(username: "member")
    appeal = filed_appeal(member: member, sanction_actor: issuer)

    sign_in(issuer)
    post admin_appeal_decide_path(appeal), params: { decision: "reversed", note: "Mine" }

    assert_redirected_to admin_appeals_path
    assert_equal "pending", appeal.reload.state
    assert_nil appeal.decided_by_id
    refute AuditLog.exists?(action: "appeals.decide")
  end

  test "a different operator can decide and the decision is recorded" do
    issuer = create_user(username: "issuer", role: "owner")
    decider = create_user(username: "decider", role: "owner")
    member = create_user(username: "member")
    appeal = filed_appeal(member: member, sanction_actor: issuer)

    sign_in(decider)
    post admin_appeal_decide_path(appeal), params: {
      decision: "reversed", note: "Evidence did not support the ban"
    }

    assert_redirected_to admin_appeals_path
    appeal.reload
    assert_equal "reversed", appeal.state
    assert_equal decider.id, appeal.decided_by_id
    assert_equal "Evidence did not support the ban", appeal.decision_note
    assert appeal.decided_at.present?

    assert AuditLog.exists?(action: "appeals.decide", target: "appeal:#{appeal.id}")
  end

  test "deciding an appeal notifies the member" do
    issuer = create_user(username: "issuer", role: "owner")
    decider = create_user(username: "decider", role: "owner")
    member = create_user(username: "member")
    appeal = filed_appeal(member: member, sanction_actor: issuer)

    sign_in(decider)
    post admin_appeal_decide_path(appeal), params: {
      decision: "reversed", note: "Ban lifted"
    }

    note = member.notifications.last
    assert note.present?, "the member should be told the outcome"
    assert_equal "admin", note.kind
    assert_match(/reversed/, note.body)
    assert_match(/Ban lifted/, note.body)
  end

  test "an appeal is not decided twice" do
    issuer = create_user(username: "issuer", role: "owner")
    decider = create_user(username: "decider", role: "owner")
    other = create_user(username: "other", role: "owner")
    member = create_user(username: "member")
    appeal = filed_appeal(member: member, sanction_actor: issuer)

    sign_in(decider)
    post admin_appeal_decide_path(appeal), params: { decision: "upheld", note: "Stands" }
    assert_equal "upheld", appeal.reload.state

    sign_in(other)
    post admin_appeal_decide_path(appeal), params: { decision: "reversed", note: "Changed mind" }

    assert_redirected_to admin_appeals_path
    assert_equal "upheld", appeal.reload.state
    assert_equal decider.id, appeal.decided_by_id
  end

  test "an operator cannot decide an appeal about their own account" do
    issuer = create_user(username: "issuer", role: "owner")
    # The member's own account, filed against itself, is the self-dealing case.
    appeal = filed_appeal(member: issuer, sanction_actor: create_user(username: "someone"))

    refute appeal.decidable_by?(issuer)
    assert_match(/You filed this appeal/, appeal.bar_reason(issuer))
    assert_raises(ArgumentError) do
      appeal.decide!(decision: "reversed", actor: issuer)
    end
  end

  test "the model refuses a barred operator even without the controller guard" do
    issuer = create_user(username: "issuer", role: "owner")
    member = create_user(username: "member")
    appeal = filed_appeal(member: member, sanction_actor: issuer)

    assert_raises(ArgumentError) do
      appeal.decide!(decision: "reversed", actor: issuer, note: "Should not record")
    end
    assert_equal "pending", appeal.reload.state
  end

  test "an unknown outcome is refused" do
    issuer = create_user(username: "issuer", role: "owner")
    decider = create_user(username: "decider", role: "owner")
    member = create_user(username: "member")
    appeal = filed_appeal(member: member, sanction_actor: issuer)

    sign_in(decider)
    post admin_appeal_decide_path(appeal), params: { decision: "maybe", note: "?" }

    assert_redirected_to admin_appeals_path
    assert_equal "pending", appeal.reload.state
  end

  test "an operator without appeals.decide cannot decide" do
    member = create_user(username: "member")
    target = create_user(username: "target")
    appeal = filed_appeal(member: target, sanction_actor: member)

    # A plain member is stopped by the admin gate before the action runs, and
    # the appeal is untouched.
    sign_in(member)
    post admin_appeal_decide_path(appeal), params: { decision: "reversed", note: "Nope" }

    assert_equal "pending", appeal.reload.state
  end

  test "a moderator holds the appeals grants and can work the queue" do
    moderator = create_user(username: "mod", role: "moderator")
    moderator_role = Role.find_by!(name: "moderator")
    assert moderator_role.permissions.exists?(key: "appeals.view")
    assert moderator_role.permissions.exists?(key: "appeals.decide")

    sign_in(moderator)
    get admin_appeals_path
    assert_response :success
  end

  test "the queue filters by state and counts each tab" do
    owner = create_user(username: "king", role: "owner")
    issuer = create_user(username: "issuer", role: "owner")
    member = create_user(username: "member")
    filed_appeal(member: member, sanction_actor: issuer)
    filed_appeal(member: member, sanction_actor: issuer, state: "upheld",
                 decided_by: owner, decision_note: "Stands", decided_at: Time.current)

    sign_in(owner)

    get admin_appeals_path
    # The default view is the pending queue.
    assert_match(/state-count">1</, response.body)

    get admin_appeals_path(state: "upheld")
    assert_response :success
    assert_match(/Upheld - the sanction stands/, response.body)

    get admin_appeals_path(state: "all")
    assert_response :success
    assert_match(/The links were not mine\./, response.body)
  end

  test "a decided appeal shows who decided it" do
    owner = create_user(username: "king", role: "owner")
    issuer = create_user(username: "issuer", role: "owner")
    member = create_user(username: "member")
    filed_appeal(member: member, sanction_actor: issuer, state: "modified",
                 decided_by: owner, decision_note: "Shortened", decided_at: Time.current)

    sign_in(owner)
    get admin_appeals_path(state: "modified")

    assert_response :success
    assert_match(/@king/, response.body)
    assert_match(/Shortened/, response.body)
  end

  test "appeals are cleared when the account is deleted" do
    owner = create_user(username: "king", role: "owner")
    member = create_user(username: "member")
    filed_appeal(member: member, sanction_actor: owner)

    sign_in(owner)
    delete admin_user_destroy_path(member)

    assert_equal 0, Appeal.where(user_id: member.id).count
  end

  # --- A reversal has to lift the sanction, not just record the word ---

  test "reversing an appeal lifts the ban and records the reversal" do
    issuer = create_user(username: "issuer", role: "owner")
    decider = create_user(username: "decider", role: "owner")
    member = create_user(username: "member")
    member.update!(is_banned: true, ban_reason: "Spam", ban_permanent: true)
    appeal = filed_appeal(member: member, sanction_actor: issuer)

    sign_in(decider)
    post admin_appeal_decide_path(appeal), params: { decision: "reversed", note: "Not spam" }

    assert_redirected_to admin_appeals_path
    member.reload
    refute member.is_banned?, "a reversed appeal must clear the ban, not just relabel it"
    assert_equal false, member.ban_permanent
    assert_nil member.ban_expires_at

    reversal = member.moderation_reversals.last
    assert reversal.present?, "the lift must be recorded as a reversal"
    assert_equal "ban", reversal.source
    assert_equal "users.ban", reversal.action
    assert_equal decider.id, reversal.actor_id
    assert_equal issuer.id, reversal.imposed_by_id
    assert_match(/Appeal ##{appeal.id}/, reversal.reason)
    assert_match(/Not spam/, reversal.reason)
  end

  test "reversing a suspension clears the suspension and records it" do
    issuer = create_user(username: "issuer", role: "owner")
    decider = create_user(username: "decider", role: "owner")
    member = create_user(username: "member")
    member.update!(is_suspended: true)
    appeal = filed_appeal(member: member, sanction_actor: issuer, sanction_kind: "suspension")

    sign_in(decider)
    post admin_appeal_decide_path(appeal), params: { decision: "reversed", note: "Overreach" }

    member.reload
    refute member.is_suspended?, "a reversed suspension must end"
    assert_equal "suspension", member.moderation_reversals.last.source
  end

  test "upholding an appeal leaves the ban in force and mints no reversal" do
    issuer = create_user(username: "issuer", role: "owner")
    decider = create_user(username: "decider", role: "owner")
    member = create_user(username: "member")
    member.update!(is_banned: true, ban_reason: "Spam", ban_permanent: true)
    appeal = filed_appeal(member: member, sanction_actor: issuer)

    sign_in(decider)
    post admin_appeal_decide_path(appeal), params: { decision: "upheld", note: "Stands" }

    assert member.reload.is_banned?, "an upheld appeal keeps the ban"
    assert_equal 0, member.moderation_reversals.count
  end

  test "a reversal is not double-recorded when the ban was already lifted" do
    issuer = create_user(username: "issuer", role: "owner")
    decider = create_user(username: "decider", role: "owner")
    member = create_user(username: "member")
    member.update!(is_banned: true, ban_reason: "Spam", ban_permanent: true)
    member.update!(is_banned: false, ban_reason: "", ban_permanent: false, ban_expires_at: nil)
    appeal = filed_appeal(member: member, sanction_actor: issuer)

    sign_in(decider)
    post admin_appeal_decide_path(appeal), params: { decision: "reversed", note: "Already clear" }

    assert_equal "reversed", appeal.reload.state
    assert_equal 0, member.reload.moderation_reversals.count
  end

  test "the audit trail records the reversal that lifted the sanction" do
    issuer = create_user(username: "issuer", role: "owner")
    decider = create_user(username: "decider", role: "owner")
    member = create_user(username: "member")
    member.update!(is_banned: true, ban_reason: "Spam", ban_permanent: true)
    appeal = filed_appeal(member: member, sanction_actor: issuer)

    sign_in(decider)
    post admin_appeal_decide_path(appeal), params: { decision: "reversed", note: "Not spam" }

    entry = AuditLog.where(action: "appeals.decide", target: "appeal:#{appeal.id}").last
    assert entry.present?
    assert_match(/reversal #\d+ lifted it/, entry.detail)
  end
end