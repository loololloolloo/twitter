require "test_helper"

# Covers the three account/cleanup features: deleting every tweet the member
# wrote, adding a second account to the browser, and the admin identity panel's
# email states.
class AccountFeaturesTest < ActionDispatch::IntegrationTest
  setup do
    @me = create_user(username: "feature_user", display_name: "Feature User")
    @other = create_user(username: "feature_other", display_name: "Other Person")
    sign_in(@me)
  end

  # --- delete all tweets -------------------------------------------------

  test "delete all tweets soft-deletes only the signed-in member's tweets" do
    mine = Tweet.create!(user: @me, body: "my first")
    mine2 = Tweet.create!(user: @me, body: "my second")
    theirs = Tweet.create!(user: @other, body: "not mine")

    assert_difference "Tweet.where(is_deleted: true).count", 2 do
      delete clear_tweets_path
    end

    assert_redirected_to settings_path
    assert mine.reload.is_deleted
    assert mine2.reload.is_deleted
    refute theirs.reload.is_deleted, "another member's tweet must be untouched"
    # The rows survive as soft deletes rather than being removed.
    assert Tweet.exists?(mine.id)
  end

  test "delete all tweets reports how many were removed" do
    Tweet.create!(user: @me, body: "one")
    Tweet.create!(user: @me, body: "two")

    delete clear_tweets_path
    assert_match(/Deleted 2 tweets/, flash[:notice])
  end

  test "delete all tweets does not count already-deleted tweets twice" do
    Tweet.create!(user: @me, body: "live")
    Tweet.create!(user: @me, body: "gone", is_deleted: true)

    delete clear_tweets_path
    assert_match(/Deleted 1 tweet\./, flash[:notice])
  end

  test "deleted tweets leave the home feed" do
    Tweet.create!(user: @me, body: "about to vanish")
    delete clear_tweets_path

    get home_path
    refute_match(/about to vanish/, response.body)
  end

  # --- add account -------------------------------------------------------

  test "a signed-in member can open the login form to add another account" do
    get login_path(add: 1)

    assert_response :success
    assert_match(/Log in to/, response.body)
  end

  test "a plain login visit still redirects a signed-in member home" do
    get login_path
    assert_redirected_to home_path
  end

  test "adding an account keeps the existing one connected" do
    assert_equal [ @me.id ], AccountsController.account_ids(session)

    post login_path, params: { identifier: @other.username, password: "password123", add: 1 }

    assert_redirected_to home_path
    ids = AccountsController.account_ids(session)
    assert_includes ids, @me.id, "the first account must stay connected"
    assert_includes ids, @other.id
    assert_equal @other.id, session[:user_id], "the added account becomes active"
  end

  test "the add-account form carries the add flag so the submit returns to the list" do
    get login_path(add: 1)
    assert_response :success
    assert_match(/type="hidden" name="add"[^>]*value="1"/, response.body)

    get login_path
    assert_no_match(/name="add"/, response.body)
  end

  test "the sidebar account menu offers a way to add another account" do
    get home_path
    assert_response :success
    assert_match(/Add an existing account/, response.body)
    assert_match(/login\?add=1/, response.body)
  end

  test "signing out keeps the other connected accounts" do
    post login_path, params: { identifier: @other.username, password: "password123", add: 1 }

    get logout_path
    assert_redirected_to login_path
    ids = AccountsController.account_ids(session)
    assert_includes ids, @me.id
    assert_nil session[:user_id]
  end

  test "removing an account from the browser drops it from the list" do
    post login_path, params: { identifier: @other.username, password: "password123", add: 1 }

    delete forget_account_path(@other.id)
    refute_includes AccountsController.account_ids(session), @other.id
  end

  # --- admin identity / email -------------------------------------------

  test "the admin identity panel shows the email and its states" do
    admin = create_user(username: "feature_admin", role: "admin")
    gmail = create_user(username: "feature_gmail", email: "person@gmail.com")
    sign_in(admin)

    get admin_user_path(gmail)
    assert_response :success
    assert_match(/Identity/, response.body)
    assert_match(/person@gmail\.com/, response.body)
    assert_match(/Email is a private domain\./, response.body)
    assert_match(/Add Email/, response.body)
  end

  test "the identity panel flags an inactive account" do
    admin = create_user(username: "feature_admin2", role: "admin")
    stale = create_user(username: "feature_stale", last_login_at: 200.days.ago)
    sign_in(admin)

    get admin_user_path(stale)
    assert_match(/Account is inactive\./, response.body)
  end

  test "an admin can change a user's email" do
    admin = create_user(username: "feature_admin3", role: "admin")
    target = create_user(username: "feature_target")
    sign_in(admin)

    post admin_user_email_path(target), params: { email: "new@example.com" }

    assert_redirected_to admin_user_path(target)
    assert_equal "new@example.com", target.reload.email
  end

  test "an invalid email is rejected" do
    admin = create_user(username: "feature_admin4", role: "admin")
    target = create_user(username: "feature_target2")
    sign_in(admin)

    post admin_user_email_path(target), params: { email: "not-an-email" }

    assert_redirected_to admin_user_path(target)
    assert_equal "feature_target2@example.com", target.reload.email
  end

  test "an email already in use by another account is rejected" do
    admin = create_user(username: "feature_admin5", role: "admin")
    taken = create_user(username: "feature_taken", email: "taken@example.com")
    target = create_user(username: "feature_target3")
    sign_in(admin)

    post admin_user_email_path(target), params: { email: "TAKEN@example.com" }

    assert_equal "feature_target3@example.com", target.reload.email
    assert_equal "taken@example.com", taken.reload.email
  end

  test "a moderator without the users.email permission cannot change an email" do
    moderator = create_user(username: "feature_mod", role: "moderator")
    target = create_user(username: "feature_target4")
    sign_in(moderator)

    post admin_user_email_path(target), params: { email: "sneaky@example.com" }

    assert_equal "feature_target4@example.com", target.reload.email
  end

  test "the user list can filter by the email states" do
    admin = create_user(username: "feature_admin6", role: "admin")
    create_user(username: "feature_prot", email: "someone@yahoo.com")
    sign_in(admin)

    get admin_users_path(status: "protected")
    assert_response :success
    assert_match(/feature_prot/, response.body)
  end
end