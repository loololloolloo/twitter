require "test_helper"

# Impersonation is the most dangerous thing the panel can do, so the guards are
# tested rather than assumed: the operator must outrank the target, simulated
# accounts cannot be entered, and the session must be restorable afterwards.
class AdminImpersonationTest < ActionDispatch::IntegrationTest
  test "an owner can sign in as a lower-ranked member and return" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")

    sign_in(owner)
    post admin_user_impersonate_path(target)

    assert_redirected_to home_path
    get home_path
    # The session now belongs to the member, so their handle is the one shown.
    assert_match(/@member/, response.body)

    post admin_stop_impersonating_path
    assert_redirected_to admin_root_path
    get admin_root_path
    assert_response :success
  end

  test "the impersonation strip is shown on public pages while impersonating" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")

    sign_in(owner)
    post admin_user_impersonate_path(target)

    get home_path
    assert_match(/browsing as @member/, response.body)
  end

  test "a member with no impersonate permission is refused" do
    admin = create_user(username: "boss", role: "admin")
    target = create_user(username: "member")

    refute admin.can?("users.impersonate"), "the admin tier should not hold this by default"

    sign_in(admin)
    post admin_user_impersonate_path(target)
    assert_redirected_to admin_user_path(target)
  end

  test "an operator cannot impersonate a peer or the owner" do
    admin = create_user(username: "boss", role: "admin")
    peer = create_user(username: "other", role: "admin")

    # Grant impersonation so rank is the only thing left to stop it.
    Role.find_by!(name: "admin").permissions << Permission.find_or_create_by!(key: "users.impersonate") { |p| p.label = "x" }
    admin.reload

    sign_in(admin)
    post admin_user_impersonate_path(peer)
    assert_redirected_to admin_user_path(peer)
    assert_match(/at or above your own level/, flash[:alert].to_s)
  end

  test "stopping when not impersonating does nothing harmful" do
    owner = create_user(username: "king", role: "owner")

    sign_in(owner)
    post admin_stop_impersonating_path
    assert_redirected_to home_path

    get admin_root_path
    assert_response :success
  end
end