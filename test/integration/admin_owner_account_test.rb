require "test_helper"

# The owner account is the one account the panel answers to. These pin the two
# halves of that: an operator who is not the owner cannot alter it, and the
# owner looking at itself still has the full set of controls.
class AdminOwnerAccountTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user(username: "twitter", role: "owner")
    @admin = create_user(username: "boss", role: "admin")
  end

  # ---------------------------------------------------------------- the page

  test "another operator sees only the read-only card for the owner" do
    sign_in(@admin)

    get admin_user_path(@owner)
    assert_response :success

    # The facts are still there...
    assert_match(/@twitter/, response.body)
    assert_match(/Account state/, response.body)
    assert_match(/Identity/, response.body)

    # ...and none of the controls are.
    assert_no_match(/Save tags/, response.body)
    assert_no_match(/Add Email/, response.body)
    assert_no_match(/Update follower count/, response.body)
    assert_no_match(/Ban user/, response.body)
    assert_no_match(/Unban user/, response.body)
    assert_no_match(/Update role/, response.body)
    assert_no_match(/Delete account/, response.body)
    assert_no_match(/Sign in as @twitter/, response.body)
  end

  test "the owner viewing itself keeps every control" do
    sign_in(@owner)

    get admin_user_path(@owner)
    assert_response :success

    assert_match(/Save tags/, response.body)
    assert_match(/Add Email/, response.body)
    assert_match(/Update follower count/, response.body)
    assert_match(/Update role/, response.body)
  end

  # -------------------------------------------------------------- the writes

  test "an admin cannot demote the owner" do
    sign_in(@admin)

    post admin_user_role_path(@owner), params: { role: "user" }

    assert_response :redirect
    assert_equal "owner", @owner.reload.role.name,
                 "the owner account must not be demoted by another operator"
  end

  test "an admin cannot revoke the owner's verified badge" do
    @owner.update!(is_verified: true)
    sign_in(@admin)

    post admin_user_verified_path(@owner)

    assert_response :redirect
    assert @owner.reload.is_verified, "another operator must not clear the owner's badge"
  end

  test "an admin cannot change the owner's follower count" do
    sign_in(@admin)

    post admin_user_followers_path(@owner), params: { followers: "999999" }

    assert_response :redirect
    assert_equal 0, @owner.reload.bonus_followers
  end

  test "an admin cannot change the owner's email" do
    sign_in(@admin)

    post admin_user_email_path(@owner), params: { email: "hijack@example.com" }

    assert_response :redirect
    assert_equal "twitter@example.com", @owner.reload.email,
                 "the sign-in identifier must not be rewritable by another operator"
  end

  test "an admin cannot ban the owner" do
    sign_in(@admin)

    post admin_user_ban_path(@owner), params: { reason: "no", duration: "permanent" }

    assert_response :redirect
    refute @owner.reload.is_banned
  end

  test "an admin cannot unban the owner" do
    @owner.update!(is_banned: true, ban_reason: "x", ban_permanent: true)
    sign_in(@admin)

    post admin_user_unban_path(@owner)

    assert_response :redirect
    assert @owner.reload.is_banned
  end

  test "an admin cannot suspend the owner" do
    sign_in(@admin)

    post admin_user_suspend_path(@owner)

    assert_response :redirect
    refute @owner.reload.is_suspended
  end

  test "an admin cannot delete the owner" do
    sign_in(@admin)

    delete admin_user_path(@owner)

    assert_response :redirect
    assert User.exists?(@owner.id), "the owner account must not be deletable"
  end

  test "an admin cannot tag the owner" do
    sign_in(@admin)

    post admin_user_tags_path(@owner), params: { tag_note: "tampered" }

    assert_response :redirect
    assert_empty @owner.reload.tag_note
  end

  test "an admin cannot impersonate the owner" do
    sign_in(@admin)

    post admin_user_impersonate_path(@owner)

    assert_response :redirect
    assert_equal @admin.id, session[:user_id], "impersonating the owner would hand over the instance"
  end

  # ------------------------------------------------------ the owner itself

  test "the owner can still change its own account" do
    sign_in(@owner)

    post admin_user_followers_path(@owner), params: { followers: "42" }
    assert_response :redirect
    assert_equal 42, @owner.reload.bonus_followers

    post admin_user_verified_path(@owner)
    assert_response :redirect
    assert @owner.reload.is_verified
  end
end
