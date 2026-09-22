require "test_helper"

# Covers warnings and the moderation history on the admin user page. A warning
# is the one moderation action that changes nothing about an account - it only
# records that the account was told - so these tests check that it is stored,
# that it expires and can be revoked, and that the history built from it and
# the audit trail reads back correctly.
class AdminWarningsTest < ActionDispatch::IntegrationTest
  test "an operator with users.warn issues a warning that is recorded" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")

    sign_in(owner)
    post admin_user_warn_path(target), params: {
      category: "spam", reason: "Posting duplicate links", duration: "30d"
    }

    assert_redirected_to admin_user_path(target)
    warning = target.user_warnings.last
    assert_equal "spam", warning.category
    assert_equal "Posting duplicate links", warning.reason
    assert_equal owner.id, warning.actor_id
    assert warning.active?
    assert warning.expires_at.present?
  end

  test "a warning with no expiry stands until it is revoked" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")

    sign_in(owner)
    post admin_user_warn_path(target), params: {
      category: "other", reason: "General notice", duration: "none"
    }

    warning = target.user_warnings.last
    assert_nil warning.expires_at
    assert warning.active?
  end

  test "a warning with no reason is refused" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")

    sign_in(owner)
    post admin_user_warn_path(target), params: { category: "spam", reason: "  " }

    assert_redirected_to admin_user_path(target)
    assert_equal 0, target.user_warnings.count
  end

  test "an unknown category falls back to other rather than failing" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")

    sign_in(owner)
    post admin_user_warn_path(target), params: {
      category: "not_a_category", reason: "Something happened"
    }

    assert_equal "other", target.user_warnings.last.category
  end

  test "revoking a warning expires it and keeps the row" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")
    warning = UserWarning.create!(user: target, actor: owner, category: "abuse", reason: "Rude")

    sign_in(owner)
    post admin_user_warning_revoke_path(target, warning)

    assert_redirected_to admin_user_path(target)
    warning.reload
    assert warning.expired?
    refute warning.active?
    # The row survives so the trail still shows the warning was given.
    assert UserWarning.exists?(warning.id)
  end

  test "an already expired warning cannot be revoked again" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")
    warning = UserWarning.create!(user: target, actor: owner, category: "abuse",
                                  reason: "Rude", expires_at: 1.day.from_now)
    first_expiry = warning.expires_at

    sign_in(owner)
    post admin_user_warning_revoke_path(target, warning)
    warning.reload
    revoked_at = warning.expires_at

    post admin_user_warning_revoke_path(target, warning)
    warning.reload
    assert_equal revoked_at, warning.expires_at
    refute_equal first_expiry, revoked_at
  end

  test "an operator cannot warn their own account" do
    owner = create_user(username: "king", role: "owner")

    sign_in(owner)
    post admin_user_warn_path(owner), params: { category: "spam", reason: "Self" }

    assert_redirected_to admin_user_path(owner)
    assert_equal 0, owner.user_warnings.count
  end

  test "a role without users.warn cannot issue a warning" do
    member = create_user(username: "member")
    target = create_user(username: "other")

    # A plain member cannot even reach the admin panel, so the request is
    # turned away before the warn action runs.
    sign_in(member)
    post admin_user_warn_path(target), params: { category: "spam", reason: "Nope" }

    assert_equal 0, target.user_warnings.count
  end

  test "a moderator holds users.warn and can issue a warning" do
    moderator = create_user(username: "mod", role: "moderator")
    target = create_user(username: "member")

    assert Role.find_by!(name: "moderator").permissions.exists?(key: "users.warn")

    sign_in(moderator)
    post admin_user_warn_path(target), params: { category: "harassment", reason: "Targeted" }

    assert_equal 1, target.user_warnings.count
    assert_equal "harassment", target.user_warnings.last.category
  end

  test "the user page shows a warning in the moderation history" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")
    UserWarning.create!(user: target, actor: owner, category: "spam",
                        reason: "Duplicate links")

    sign_in(owner)
    get admin_user_path(target)

    assert_response :success
    assert_match(/Moderation history/, response.body)
    assert_match(/mod-history/, response.body)
    assert_match(/Warning: Spam or platform manipulation/, response.body)
    assert_match(/Duplicate links/, response.body)
    assert_match(/@king/, response.body)
  end

  test "the history is stacked newest first" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")
    UserWarning.create!(user: target, actor: owner, category: "spam", reason: "Older warning",
                        created_at: 3.days.ago)
    UserWarning.create!(user: target, actor: owner, category: "abuse", reason: "Newer warning",
                        created_at: 1.hour.ago)

    sign_in(owner)
    get admin_user_path(target)

    body = response.body
    newer = body.index("Newer warning")
    older = body.index("Older warning")
    assert newer.present? && older.present?
    assert newer < older, "the newer warning should render above the older one"
  end

  test "the history carries the ban and staff changes from the audit trail" do
    owner = create_user(username: "king", role: "owner")
    approver = create_user(username: "watch", role: "owner")
    target = create_user(username: "member")

    sign_in(owner)
    post admin_user_ban_path(target), params: { reason: "Evading", duration: "permanent" }
    request = ApprovalRequest.find_by!(user: target, action_key: "permanent_ban")

    # A permanent ban only reaches the history once the second operator has
    # approved it; the approved change records the same `users.ban` entry the
    # single-operator timed ban does.
    sign_in(approver)
    post admin_approval_decide_path(request), params: { decision: "approved" }

    get admin_user_path(target)
    assert_response :success
    assert_match(/Ban changed/, response.body)
    assert_match(/banned for permanent: Evading/, response.body)
  end

  test "a warning appears once, not twice, in the history" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")

    sign_in(owner)
    post admin_user_warn_path(target), params: { category: "spam", reason: "Once only" }

    get admin_user_path(target)

    # The warning renders from its own row and its audit entry is deliberately
    # excluded from the trail-derived entries, so within the history block the
    # reason shows a single time. (It still appears in the raw audit table
    # below, which is a separate rendering of the same event.)
    history = response.body[/<ol class="mod-history">.*?<\/ol>/m]
    assert history.present?, "the moderation history should render"
    assert_equal 1, history.scan("Once only").size
  end

  test "the active warning count is reported on the user page" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")
    UserWarning.create!(user: target, actor: owner, category: "spam", reason: "Standing")
    UserWarning.create!(user: target, actor: owner, category: "abuse",
                        reason: "Lapsed", expires_at: 1.day.ago)

    sign_in(owner)
    get admin_user_path(target)

    assert_response :success
    assert_match(/1 active/, response.body)
    assert_match(/2 issued in total/, response.body)
  end

  test "an expired warning has no revoke control" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")
    UserWarning.create!(user: target, actor: owner, category: "spam",
                        reason: "Lapsed", expires_at: 1.day.ago)

    sign_in(owner)
    get admin_user_path(target)

    assert_no_match(%r{/admin/users/#{target.id}/warnings/\d+/revoke}, response.body)
  end

  test "a user with no moderation history says so" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")

    sign_in(owner)
    get admin_user_path(target)

    assert_match(/No moderation actions have been taken against this account/, response.body)
  end

  test "warnings are cleared when the account is deleted" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")
    UserWarning.create!(user: target, actor: owner, category: "spam", reason: "Gone")

    sign_in(owner)
    delete admin_user_destroy_path(target)

    assert_equal 0, UserWarning.where(user_id: target.id).count
  end

  test "warning state reads correctly for each expiry" do
    target = create_user(username: "member")

    standing = UserWarning.new(user: target, category: "spam", reason: "x")
    assert standing.active?
    refute standing.expired?

    lapsed = UserWarning.new(user: target, category: "spam", reason: "x",
                             expires_at: 1.minute.ago)
    assert lapsed.expired?
    refute lapsed.active?
  end

  test "issuing a warning notifies the member with the reason and strike count" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")

    sign_in(owner)
    post admin_user_warn_path(target), params: {
      category: "harassment", reason: "Targeted replies", duration: "none"
    }

    note = target.notifications.last
    assert note.present?, "the member should be notified"
    assert_equal "admin", note.kind
    assert_equal owner.id, note.actor_id
    assert_match(/Targeted replies/, note.body)
    assert_match(/Standing warnings: 1/, note.body)
  end

  test "a warning that is refused does not notify the member" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")

    sign_in(owner)
    post admin_user_warn_path(target), params: { category: "spam", reason: "  " }

    assert_equal 0, target.notifications.count
  end

  test "the strike count falls when a warning is revoked" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")
    warning = UserWarning.create!(user: target, actor: owner, category: "spam", reason: "Standing")

    assert_equal 1, target.strike_count

    sign_in(owner)
    post admin_user_warning_revoke_path(target, warning)

    assert_equal 0, target.reload.strike_count
  end

  test "the escalation ladder reads the rung the strike count reaches" do
    target = create_user(username: "member")

    assert_nil target.strike_rung
    assert_equal StrikeLadder.all.first, target.next_strike_rung

    UserWarning.create!(user: target, actor: target, category: "spam", reason: "one")
    assert_equal "Notice", target.reload.strike_rung.label
    assert_equal "Elevated", target.next_strike_rung.label

    UserWarning.create!(user: target, actor: target, category: "spam", reason: "two")
    UserWarning.create!(user: target, actor: target, category: "spam", reason: "three")
    assert_equal "Elevated", target.reload.strike_rung.label
    assert_equal 2, StrikeLadder.remaining(3)
    assert_nil StrikeLadder.next(7)
  end

  test "the user page shows the ladder and the next consequence" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")
    UserWarning.create!(user: target, actor: owner, category: "spam", reason: "Standing")

    sign_in(owner)
    get admin_user_path(target)

    assert_response :success
    assert_match(/strike-ladder/, response.body)
    assert_match(/Notice/, response.body)
    assert_match(/more warnings/, response.body)
  end
end
