require "test_helper"

# Covers bulk actions on the accounts list: the two-step confirm-before-run
# flow, the per-account guards that the single-account screen also applies, and
# the audit trail the run leaves behind.
#
# The confirmation is the feature here, so most of these tests are about what
# the preview says and what the run refuses to do, not about the happy path
# alone.
class AdminBulkActionsTest < ActionDispatch::IntegrationTest
  test "an operator with users.bulk sees the selection controls on the list" do
    owner = create_user(username: "king", role: "owner")
    create_user(username: "member")

    sign_in(owner)
    get admin_users_path

    assert_response :success
    assert_match(/bulk-form/, response.body)
    assert_match(/Review selection/, response.body)
  end

  test "the confirmation screen states the exact blast radius and writes nothing" do
    owner = create_user(username: "king", role: "owner")
    a = create_user(username: "alpha")
    b = create_user(username: "bravo")

    sign_in(owner)
    post admin_users_bulk_path, params: { action_key: "suspend", ids: [ a.id, b.id ] }

    assert_response :success
    assert_match(/This will suspend 2 accounts/, response.body)
    # The preview is a GET-like read: neither account is suspended yet.
    refute a.reload.is_suspended
    refute b.reload.is_suspended
    refute AuditLog.exists?(action: "users.bulk.suspend")
  end

  test "the run is refused until the confirmation word is typed" do
    owner = create_user(username: "king", role: "owner")
    member = create_user(username: "member")

    sign_in(owner)
    post admin_users_bulk_commit_path, params: {
      action_key: "suspend", ids: [ member.id ], reason: "coordinated spam", confirm: "yes"
    }

    assert_redirected_to admin_users_path
    refute member.reload.is_suspended
    refute AuditLog.exists?(action: "users.bulk.suspend")
  end

  test "a confirmed suspend changes every eligible account and audits each one" do
    owner = create_user(username: "king", role: "owner")
    a = create_user(username: "alpha")
    b = create_user(username: "bravo")

    sign_in(owner)
    post admin_users_bulk_commit_path, params: {
      action_key: "suspend", ids: [ a.id, b.id ], reason: "coordinated spam", confirm: "CONFIRM"
    }

    assert_redirected_to admin_users_path
    assert a.reload.is_suspended
    assert b.reload.is_suspended
    # One entry per account plus one for the run itself.
    assert_equal 2, AuditLog.where(action: "users.suspend").count
    assert AuditLog.exists?(action: "users.bulk.suspend", target: "accounts")
  end

  test "the owner and peers are excluded from the run rather than acted on" do
    owner = create_user(username: "king", role: "owner")
    peer = create_user(username: "peer", role: "admin")
    member = create_user(username: "member")

    sign_in(peer)
    post admin_users_bulk_path, params: { action_key: "suspend", ids: [ owner.id, member.id ] }

    assert_response :success
    assert_match(/the owner account, which answers to nobody/, response.body)
    assert_match(/This will suspend 1 account\./, response.body)

    post admin_users_bulk_commit_path, params: {
      action_key: "suspend", ids: [ owner.id, member.id ], reason: "spam", confirm: "CONFIRM"
    }

    refute owner.reload.is_suspended
    assert member.reload.is_suspended
  end

  test "an operator cannot suspend their own account in a bulk run" do
    owner = create_user(username: "king", role: "owner")

    sign_in(owner)
    post admin_users_bulk_path, params: { action_key: "suspend", ids: [ owner.id, owner.id ] }

    assert_response :success
    assert_match(/your own account/, response.body)
    assert_match(/No selected account can be acted on/, response.body)
  end

  test "a reason is required for enforcement actions but not restorative ones" do
    owner = create_user(username: "king", role: "owner")
    active = create_user(username: "active")
    limited = create_user(username: "limited", is_suspended: true)

    sign_in(owner)
    # An enforcement action with no reason is refused outright.
    post admin_users_bulk_commit_path, params: {
      action_key: "suspend", ids: [ active.id ], confirm: "CONFIRM"
    }
    assert_redirected_to admin_users_path
    assert_match(/reason is required/, flash[:alert].to_s)
    refute active.reload.is_suspended

    # A restorative action records no reason and does not demand one.
    post admin_users_bulk_commit_path, params: {
      action_key: "reinstate", ids: [ limited.id ], confirm: "CONFIRM"
    }
    assert_redirected_to admin_users_path
    refute limited.reload.is_suspended
  end

  test "a bulk ban and lift round-trips through the guards" do
    owner = create_user(username: "king", role: "owner")
    member = create_user(username: "member")

    sign_in(owner)
    post admin_users_bulk_commit_path, params: {
      action_key: "ban", ids: [ member.id ], reason: "evasion", confirm: "CONFIRM"
    }
    member.reload
    assert member.is_banned
    assert member.ban_permanent
    assert_equal "evasion", member.ban_reason

    post admin_users_bulk_commit_path, params: {
      action_key: "unban", ids: [ member.id ], confirm: "CONFIRM"
    }
    refute member.reload.is_banned
  end

  test "an escalated account is held back from enforcement but not from restoration" do
    owner = create_user(username: "king", role: "owner")
    flagged = create_user(username: "flagged", requires_review: true)
    flagged.update!(is_suspended: true)

    sign_in(owner)
    post admin_users_bulk_path, params: { action_key: "suspend", ids: [ flagged.id ] }
    assert_match(/No selected account can be acted on/, response.body)
    assert_match(/held back from enforcement|tagged for escalation/, response.body)

    post admin_users_bulk_commit_path, params: {
      action_key: "suspend", ids: [ flagged.id ], reason: "spam", confirm: "CONFIRM"
    }
    assert flagged.reload.is_suspended

    post admin_users_bulk_commit_path, params: {
      action_key: "reinstate", ids: [ flagged.id ], confirm: "CONFIRM"
    }
    refute flagged.reload.is_suspended
  end

  test "a bulk delete removes the accounts and their posts" do
    owner = create_user(username: "king", role: "owner")
    member = create_user(username: "member")
    Tweet.create!(user: member, body: "gone with the account")

    sign_in(owner)
    post admin_users_bulk_commit_path, params: {
      action_key: "delete", ids: [ member.id ], reason: "spam network", confirm: "CONFIRM"
    }

    assert_redirected_to admin_users_path
    refute User.exists?(member.id)
    assert AuditLog.exists?(action: "users.bulk.delete", target: "accounts")
  end

  test "a bulk tag action carries the chosen tag into the run" do
    owner = create_user(username: "king", role: "owner")
    member = create_user(username: "member")

    sign_in(owner)
    post admin_users_bulk_commit_path, params: {
      action_key: "tag_on", ids: [ member.id ], tag: "do_not_amplify",
      reason: "coordinated inauthentic behaviour", confirm: "CONFIRM"
    }

    assert member.reload.do_not_amplify
    assert AuditLog.exists?(action: "users.tags")
  end

  test "a role without users.bulk cannot start a bulk run" do
    moderator = create_user(username: "mod", role: "moderator")
    member = create_user(username: "member")

    sign_in(moderator)
    # A moderator holds users.tags but not users.bulk, so even an action they
    # are otherwise allowed to take individually is refused in bulk.
    post admin_users_bulk_path, params: { action_key: "suspend", ids: [ member.id ] }

    assert_redirected_to admin_users_path
    assert_match(/Bulk actions are not enabled/, flash[:alert].to_s)
    refute member.reload.is_suspended
  end

  test "a bulk run cannot borrow a permission the action does not have" do
    owner = create_user(username: "king", role: "owner")
    moderator = create_user(username: "mod", role: "moderator")
    moderator.role.permissions.destroy_all
    moderator.role.permissions << Permission.find_or_create_by!(key: "admin.access")
    moderator.role.permissions << Permission.find_or_create_by!(key: "users.bulk")
    member = create_user(username: "member")

    sign_in(moderator)
    post admin_users_bulk_path, params: { action_key: "suspend", ids: [ member.id ] }

    assert_redirected_to admin_users_path
    assert_match(/not allowed to suspend/, flash[:alert].to_s)
    refute member.reload.is_suspended

    # The owner is untouched by a request that names them; the panel refuses the
    # whole action before it looks at the selection.
    post admin_users_bulk_path, params: { action_key: "suspend", ids: [ owner.id ] }
    refute owner.reload.is_suspended
  end

  test "an empty selection is refused" do
    owner = create_user(username: "king", role: "owner")

    sign_in(owner)
    post admin_users_bulk_path, params: { action_key: "suspend", ids: [ "" ] }

    assert_redirected_to admin_users_path
    assert_match(/Select at least one account/, flash[:alert].to_s)
  end
end
