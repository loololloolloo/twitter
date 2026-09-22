require "test_helper"

# Covers the four-eyes approval queue. The panel's three hardest-to-undo actions
# - permanent suspension, email change and handle release - do not take effect
# on the operator's click. They are filed as a pending request and applied only
# when a *different* operator approves. These tests check that the account is
# untouched while a request is pending, that the filer is barred from deciding
# it (in the model, not just the screen), and that an approval is the thing that
# actually mutates the account.
class AdminApprovalsTest < ActionDispatch::IntegrationTest
  def file_request(action_key:, user:, actor:, payload: {})
    ApprovalRequest.create!(
      user: user,
      requested_by: actor,
      action_key: action_key,
      request_note: "filed in test",
      payload: payload.merge(reason: "filed in test").to_json
    )
  end

  test "a permanent ban is filed, not applied, and the queue states the impact" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")

    sign_in(owner)
    post admin_user_ban_path(target), params: { reason: "Ban evasion", duration: "permanent" }

    assert_redirected_to admin_user_path(target)
    refute target.reload.is_banned

    request = ApprovalRequest.find_by!(user: target, action_key: "permanent_ban")
    assert request.pending?
    assert_equal owner.id, request.requested_by_id

    get admin_approvals_path
    assert_response :success
    assert_match(/Permanent suspension/, response.body)
    # The consequence is spelled out rather than left as a bare action name.
    assert_match(/Approving will: Permanently ban the account/, response.body)
    # The filer sees the bar, not an approve button.
    assert_match(/You cannot decide this request/, response.body)
    assert_no_match(/Record decision/, response.body)
  end

  test "the requester cannot decide their own request through a direct call" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")
    request = file_request(action_key: "permanent_ban", user: target, actor: owner)

    sign_in(owner)
    post admin_approval_decide_path(request), params: { decision: "approved" }

    assert_redirected_to admin_approvals_path
    assert request.reload.pending?
    refute target.reload.is_banned
  end

  test "a different operator approving applies the change and records both actors" do
    filer = create_user(username: "filer", role: "admin")
    approver = create_user(username: "approver", role: "owner")
    target = create_user(username: "member")
    request = file_request(action_key: "permanent_ban", user: target, actor: filer)

    sign_in(approver)
    post admin_approval_decide_path(request), params: { decision: "approved" }

    request.reload
    assert_equal "approved", request.state
    assert_equal approver.id, request.decided_by_id
    assert_equal filer.id, request.requested_by_id

    target.reload
    assert target.is_banned
    assert target.ban_permanent
    assert_nil target.ban_expires_at

    # The applied change reads in the account history as a ban, and the audit
    # trail names the filer and the approver separately.
    assert AuditLog.exists?(action: "users.ban", target: "user:#{target.id}")
    assert AuditLog.exists?(action: "approvals.decide", target: "user:#{target.id}")
    assert AuditLog.exists?(action: "approvals.apply", target: "user:#{target.id}")
  end

  test "rejecting leaves the account untouched and requires a reason" do
    filer = create_user(username: "filer", role: "admin")
    approver = create_user(username: "approver", role: "owner")
    target = create_user(username: "member")
    request = file_request(action_key: "permanent_ban", user: target, actor: filer)

    sign_in(approver)
    post admin_approval_decide_path(request), params: { decision: "rejected", note: "" }

    assert_redirected_to admin_approvals_path
    assert request.reload.pending?

    post admin_approval_decide_path(request), params: { decision: "rejected", note: "Insufficient evidence" }

    request.reload
    assert_equal "rejected", request.state
    assert_equal "Insufficient evidence", request.decision_note
    refute target.reload.is_banned
    # A rejected request is never applied.
    assert_no_match(/users.ban/, AuditLog.where(target: "user:#{target.id}").pluck(:action).join(","))
  end

  test "an email change is gated and lands only on approval" do
    filer = create_user(username: "filer", role: "admin")
    approver = create_user(username: "approver", role: "owner")
    target = create_user(username: "member")

    sign_in(filer)
    post admin_user_email_path(target), params: { email: "moved@example.com" }

    assert_equal "member@example.com", target.reload.email
    request = ApprovalRequest.find_by!(user: target, action_key: "email_change")
    assert request.pending?

    sign_in(approver)
    post admin_approval_decide_path(request), params: { decision: "approved" }

    assert_equal "moved@example.com", target.reload.email
  end

  test "a handle release is gated and lands only on approval" do
    filer = create_user(username: "filer", role: "admin")
    approver = create_user(username: "approver", role: "owner")
    target = create_user(username: "member")

    sign_in(filer)
    post admin_user_handle_path(target), params: { handle: "renamed" }

    assert_equal "member", target.reload.username
    request = ApprovalRequest.find_by!(user: target, action_key: "handle_release")
    assert request.pending?

    sign_in(approver)
    post admin_approval_decide_path(request), params: { decision: "approved" }

    assert_equal "renamed", target.reload.username
    assert AuditLog.exists?(action: "users.handle", target: "user:#{target.id}")
  end

  test "a second pending request for the same action is refused" do
    filer = create_user(username: "filer", role: "admin")
    target = create_user(username: "member")

    sign_in(filer)
    post admin_user_email_path(target), params: { email: "one@example.com" }
    post admin_user_email_path(target), params: { email: "two@example.com" }

    assert_equal 1, ApprovalRequest.where(user: target, action_key: "email_change", state: "pending").count
    assert_equal "member@example.com", target.reload.email
  end

  test "the owner account cannot be filed against by another operator" do
    owner = create_user(username: "king", role: "owner")
    admin = create_user(username: "admin2", role: "admin")

    sign_in(admin)
    post admin_user_ban_path(owner), params: { reason: "Coup", duration: "permanent" }

    refute ApprovalRequest.exists?(user: owner, action_key: "permanent_ban")
    refute owner.reload.is_banned
  end

  test "an operator without approvals.decide cannot open or decide the queue" do
    moderator = create_user(username: "mod", role: "moderator")
    filer = create_user(username: "filer", role: "admin")
    target = create_user(username: "member")
    request = file_request(action_key: "permanent_ban", user: target, actor: filer)

    sign_in(moderator)
    get admin_approvals_path
    assert_redirected_to admin_root_path

    post admin_approval_decide_path(request), params: { decision: "approved" }
    assert_redirected_to admin_root_path
    assert request.reload.pending?
    refute target.reload.is_banned
  end

  test "a timed ban is not gated" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")

    sign_in(owner)
    post admin_user_ban_path(target), params: { reason: "Spam", duration: "3d" }

    assert target.reload.is_banned
    refute target.ban_permanent
    refute ApprovalRequest.exists?(user: target)
  end
end
