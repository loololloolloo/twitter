require "test_helper"

# Covers the shift handover digest. The digest is a read-only roll-up: the open
# queues the viewer can reach, the enforcement and decision actions recorded in
# the last shift, and the items a second operator has to take because separation
# of duties bars the current one. These tests check the counts, the window on
# the audit trail, and that each of those sections is gated on the permission
# that owns it.
class AdminHandoverTest < ActionDispatch::IntegrationTest
  def filed_appeal(member:, sanction_actor:, state: "pending")
    Appeal.create!(
      user: member,
      sanction_kind: "ban",
      sanction_reason: "Repeated spam",
      sanction_actor: sanction_actor,
      body: "The links were not mine.",
      state: state
    )
  end

  test "the owner sees the open queues with their counts" do
    owner = create_user(username: "king", role: "owner")
    member = create_user(username: "member")
    create_user(username: "spammer")
    filed_appeal(member: member, sanction_actor: owner)

    Report.create!(
      user: member,
      reporter: owner,
      category: "spam",
      detail: "Reported",
      state: "open"
    )
    ModerationCase.create!(
      title: "Repeated reports", summary: "Same account", user: member, opened_by: owner
    )
    VerificationRequest.create!(
      user: member, category: "individual", body: "Please verify me"
    )
    ApprovalRequest.create!(
      user: member, action_key: "permanent_ban", requested_by: owner,
      payload: { reason: "Evasion" }.to_json
    )

    sign_in(owner)
    get admin_handover_path

    assert_response :success
    assert_match(/Shift handover/, response.body)
    # Each tile names the queue and its live count, and links into it.
    assert_match(/Open reports/, response.body)
    assert_match(/Open cases/, response.body)
    assert_match(/Pending appeals/, response.body)
    assert_match(/Verification requests/, response.body)
    assert_match(/Four-eyes approvals/, response.body)
    assert_includes response.body, admin_reports_path(state: "open")
    assert_includes response.body, admin_cases_path(state: "open")
    assert_includes response.body, admin_appeals_path(state: "pending")
  end

  test "recent actions are windowed to the shift and trimmed to the meaningful ones" do
    owner = create_user(username: "king", role: "owner")
    member = create_user(username: "member")

    AuditLog.append(actor: owner, action: "users.ban", target: "user:#{member.id}",
                    detail: "banned for spam")
    # Outside the window: an old action is not part of this handover.
    old = AuditLog.append(actor: owner, action: "users.warn", target: "user:#{member.id}",
                          detail: "ancient warning")
    AuditLog.where(id: old.id).update_all(created_at: 2.days.ago)
    # A read-only maintenance entry is recorded but is not relayed at handover.
    AuditLog.append(actor: owner, action: "maintenance.vacuum", target: "database",
                    detail: "reclaimed 1024 byte(s)")

    sign_in(owner)
    get admin_handover_path

    assert_response :success
    assert_match(/Changed in the last 6 hours/, response.body)
    assert_match(/banned for spam/, response.body)
    assert_no_match(/ancient warning/, response.body)
    assert_no_match(/reclaimed 1024 byte\(s\)/, response.body)
  end

  test "the digest names the items a second operator must take" do
    issuer = create_user(username: "issuer", role: "owner")
    member = create_user(username: "member")
    filed_appeal(member: member, sanction_actor: issuer)
    ModerationCase.create!(
      title: "Repeated reports", summary: "Same account", user: member, opened_by: issuer
    )

    sign_in(issuer)
    get admin_handover_path

    assert_response :success
    assert_match(/Needs a second operator/, response.body)
    assert_match(/cannot be closed by you/, response.body)
    assert_match(/You issued the ban this appeal contests\./, response.body)
    assert_match(/You opened this case; it has to be decided by someone else\./, response.body)
  end

  test "an operator with no bars sees nothing waiting on a second operator" do
    issuer = create_user(username: "issuer", role: "owner")
    viewer = create_user(username: "viewer", role: "owner")
    member = create_user(username: "member")
    filed_appeal(member: member, sanction_actor: issuer)

    sign_in(viewer)
    get admin_handover_path

    assert_response :success
    assert_match(/Needs a second operator/, response.body)
    assert_no_match(/You issued the ban this appeal contests\./, response.body)
  end

  test "a moderator without the handover grant is refused" do
    create_user(username: "king", role: "owner")
    limited = create_user(username: "limited", role: "moderator")
    # Strip the grant so the moderator holds users.view but not handover.view.
    role = limited.role
    permission = Permission.find_by!(key: "handover.view")
    RolePermission.where(role_id: role.id, permission_id: permission.id).delete_all

    sign_in(limited)
    get admin_handover_path

    assert_redirected_to admin_root_path
    assert_match(/handover\.view/, flash[:alert])
  end

  test "the recent block is withheld from an operator without audit.view" do
    owner = create_user(username: "king", role: "owner")
    viewer = create_user(username: "viewer", role: "moderator")
    role = viewer.role
    permission = Permission.find_by!(key: "audit.view")
    RolePermission.where(role_id: role.id, permission_id: permission.id).delete_all

    AuditLog.append(actor: owner, action: "users.ban", target: "user:1", detail: "banned for spam")

    sign_in(viewer)
    get admin_handover_path

    assert_response :success
    assert_match(/Reading the audit trail needs the audit\.view permission/, response.body)
    assert_no_match(/banned for spam/, response.body)
  end
end
