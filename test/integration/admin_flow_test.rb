require "test_helper"

# Covers the admin panel end to end through real HTTP requests: who can get in,
# what each action does to the database, and the rank rules that stop a
# moderator from acting on an administrator.
class AdminFlowTest < ActionDispatch::IntegrationTest
  test "the admin rail shows the operator card instead of a sentence" do
    owner = create_user(username: "owner_one", role: "owner")
    sign_in(owner)

    get admin_root_path
    assert_response :success

    assert_match(/rail-operator/, response.body)
    assert_match(/@owner_one/, response.body)
    assert_match(/pill-role/, response.body)
    # The old inline "Signed in as ... role: ... permissions" string is gone.
    assert_no_match(/Signed in as/, response.body)
  end

  test "the admin rail carries the panel links as a sidebar" do
    owner = create_user(username: "owner_one", role: "owner")
    sign_in(owner)

    get admin_root_path
    # The panel keeps both surfaces, and they carry different things: the
    # toolbar holds the working tools, the rail holds the queues and reference
    # screens. The rail does not repeat a toolbar tab.
    assert_match(%r{<nav class="topnav">}, response.body)
    assert_match(%r{href="/admin/lookup"}, response.body)
    assert_match(%r{class="rail-group"}, response.body)
    assert_match(%r{href="/admin/audit"}, response.body)
    refute_match(%r{<nav class="admin-nav"}, response.body)
  end

  test "the operator card identifies the signed-in operator" do
    admin = create_user(username: "boss", role: "admin")
    sign_in(admin)

    get admin_root_path

    assert_match(/class="rail-operator"/, response.body)
    assert_match(/@boss/, response.body)
    assert_match(/pill-role/, response.body)
    # The old card reported a permission total as "n of m"; it was removed as
    # noise, so the operator card no longer prints a fraction at all.
    assert_no_match(/of #{Permission.count}/, response.body)
  end

  test "an announcement posted from the rail reaches the public site" do
    owner = create_user(username: "owner_one", role: "owner")
    sign_in(owner)

    post admin_sidebar_announcement_path, params: { announcement: "Scheduled maintenance tonight" }
    assert_redirected_to admin_root_path
    assert_equal "Scheduled maintenance tonight", SiteSetting.announcement

    get home_path
    assert_match(/Scheduled maintenance tonight/, response.body)
    assert_match(/announcement-banner/, response.body)
  end

  test "clearing the announcement removes the banner" do
    owner = create_user(username: "owner_one", role: "owner")
    sign_in(owner)

    SiteSetting.put("announcement", "Temporary notice")
    post admin_sidebar_announcement_path, params: { announcement: "" }
    assert_equal "", SiteSetting.announcement

    get home_path
    assert_no_match(/announcement-banner/, response.body)
  end

  test "only editors may post an announcement" do
    member = create_user(username: "member")
    sign_in(member)

    post admin_sidebar_announcement_path, params: { announcement: "nope" }
    assert_redirected_to home_path
    assert_equal "", SiteSetting.announcement
  end

  test "a regular member cannot reach the admin panel" do
    member = create_user(username: "member")
    sign_in(member)

    get admin_root_path
    assert_redirected_to home_path
    follow_redirect!
    assert_match(/do not have access/i, response.body)
  end

  test "owner sees the dashboard with live counts" do
    owner = create_user(username: "owner_one", role: "owner")
    create_user(username: "someone")

    sign_in(owner)
    get admin_root_path

    assert_response :success
    assert_match(/Dashboard/, response.body)
    assert_match(/owner_one/, response.body)
    assert_match(/all #{Permission.count}/, response.body)
  end

  test "admin lists and searches users" do
    admin = create_user(username: "boss", role: "admin")
    create_user(username: "findme", display_name: "Find Me")
    create_user(username: "hidden")

    sign_in(admin)
    get admin_users_path(q: "findme")

    assert_response :success
    assert_match(/findme/, response.body)
    assert_no_match(/@hidden/, response.body)
  end

  test "admin bans a user with a reason and duration, then unbans" do
    admin = create_user(username: "boss", role: "admin")
    target = create_user(username: "troll")

    sign_in(admin)

    post admin_user_ban_path(target), params: { reason: "Harassment", duration: "3d" }
    assert_redirected_to admin_user_path(target)

    target.reload
    assert target.is_banned
    assert_equal "Harassment", target.ban_reason
    refute target.ban_permanent
    assert_in_delta 3.days.from_now, target.ban_expires_at, 60
    assert AuditLog.exists?(action: "users.ban", target: "user:#{target.id}")

    post admin_user_unban_path(target)
    target.reload
    refute target.is_banned
    assert_nil target.ban_expires_at
  end

  test "a permanent ban has no expiry" do
    admin = create_user(username: "boss", role: "admin")
    target = create_user(username: "troll")

    sign_in(admin)
    post admin_user_ban_path(target), params: { reason: "Spam", duration: "permanent" }

    target.reload
    assert target.is_banned
    assert target.ban_permanent
    assert_nil target.ban_expires_at
  end

  test "a ban without a reason is rejected" do
    admin = create_user(username: "boss", role: "admin")
    target = create_user(username: "troll")

    sign_in(admin)
    post admin_user_ban_path(target), params: { reason: "", duration: "1d" }

    refute target.reload.is_banned
  end

  test "an admin cannot ban a peer at the same rank" do
    admin = create_user(username: "boss", role: "admin")
    peer = create_user(username: "peer", role: "admin")

    sign_in(admin)
    post admin_user_ban_path(peer), params: { reason: "Because", duration: "1d" }

    refute peer.reload.is_banned
  end

  test "an admin cannot ban the owner" do
    admin = create_user(username: "boss", role: "admin")
    owner = create_user(username: "king", role: "owner")

    sign_in(admin)
    post admin_user_ban_path(owner), params: { reason: "Coup", duration: "1d" }

    refute owner.reload.is_banned
  end

  test "an admin cannot ban themselves" do
    admin = create_user(username: "boss", role: "admin")

    sign_in(admin)
    post admin_user_ban_path(admin), params: { reason: "Oops", duration: "1d" }

    refute admin.reload.is_banned
  end

  test "bot followers raise the displayed count without creating users" do
    admin = create_user(username: "boss", role: "admin")
    target = create_user(username: "celebrity")
    create_user(username: "real_fan")

    Follow.create!(follower: User.find_by(username: "real_fan"), followee: target)

    sign_in(admin)
    post admin_user_followers_path(target), params: { followers: "50000" }

    target.reload
    assert_equal 50_000, target.bonus_followers
    assert_equal 50_001, target.follower_count
    # No fake follower rows were invented.
    assert_equal 1, Follow.where(followee_id: target.id).count
    assert_equal 3, User.count
  end

  test "follower count rejects non-numeric input" do
    admin = create_user(username: "boss", role: "admin")
    target = create_user(username: "celebrity")

    sign_in(admin)
    post admin_user_followers_path(target), params: { followers: "banana" }

    assert_equal 0, target.reload.bonus_followers
  end

  test "a moderator cannot set follower counts" do
    moderator = create_user(username: "mod", role: "moderator")
    target = create_user(username: "celebrity")

    sign_in(moderator)
    post admin_user_followers_path(target), params: { followers: "999" }

    assert_equal 0, target.reload.bonus_followers
  end

  test "verified badge can be granted and revoked" do
    admin = create_user(username: "boss", role: "admin")
    target = create_user(username: "notable")

    sign_in(admin)
    post admin_user_verified_path(target)
    assert target.reload.is_verified

    post admin_user_verified_path(target)
    refute target.reload.is_verified
  end

  test "role assignment is owner-only, as in the legacy permission model" do
    owner = create_user(username: "king", role: "owner")
    admin = create_user(username: "boss", role: "admin")
    target = create_user(username: "striver")

    # `users.roles` is not granted to the admin role, so an admin cannot
    # promote anyone even to moderator.
    sign_in(admin)
    post admin_user_role_path(target), params: { role: "moderator" }
    assert_equal "user", target.reload.role.name

    # The owner holds every permission and can assign any role.
    sign_in(owner)
    post admin_user_role_path(target), params: { role: "admin" }
    assert_equal "admin", target.reload.role.name
  end

  test "suspend signs the user out and reinstate restores access" do
    admin = create_user(username: "boss", role: "admin")
    target = create_user(username: "rapscallion")

    sign_in(admin)
    post admin_user_suspend_path(target)

    assert target.reload.is_suspended
    assert_equal 0, target.sessions.count

    post admin_user_suspend_path(target)
    refute target.reload.is_suspended
  end

  test "an admin can delete a regular member but not the owner" do
    admin = create_user(username: "boss", role: "admin")
    member = create_user(username: "goner")
    owner = create_user(username: "king", role: "owner")

    sign_in(admin)
    delete admin_user_path(member)
    refute User.exists?(member.id)

    delete admin_user_path(owner)
    assert User.exists?(owner.id)
  end
end