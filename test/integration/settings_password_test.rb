require "test_helper"

# Password changes go through SettingsController#password, which verifies the
# current password before replacing the stored hash.
class SettingsPasswordTest < ActionDispatch::IntegrationTest
  test "a correct current password replaces the hash and the new one works" do
    user = create_user(username: "changer")
    sign_in(user)

    post settings_password_path, params: {
      current_password: "password123",
      password: "newpassword456",
      password_confirm: "newpassword456"
    }

    assert_redirected_to settings_path
    user.reload
    assert user.password_matches?("newpassword456")
    refute user.password_matches?("password123")
    assert AuditLog.exists?(action: "user.password", target: "user:#{user.id}")
  end

  test "the new password can actually sign in" do
    user = create_user(username: "changer")
    sign_in(user)

    post settings_password_path, params: {
      current_password: "password123",
      password: "newpassword456",
      password_confirm: "newpassword456"
    }

    delete logout_path
    sign_in_with(identifier: "changer", password: "newpassword456")
    assert_redirected_to home_path
  end

  test "a wrong current password is refused" do
    user = create_user(username: "changer")
    sign_in(user)

    post settings_password_path, params: {
      current_password: "wrongpassword",
      password: "newpassword456",
      password_confirm: "newpassword456"
    }

    assert_redirected_to settings_path
    assert user.reload.password_matches?("password123")
  end

  test "mismatched confirmation is refused" do
    user = create_user(username: "changer")
    sign_in(user)

    post settings_password_path, params: {
      current_password: "password123",
      password: "newpassword456",
      password_confirm: "different789"
    }

    assert user.reload.password_matches?("password123")
  end

  test "a short new password is refused" do
    user = create_user(username: "changer")
    sign_in(user)

    post settings_password_path, params: {
      current_password: "password123",
      password: "short",
      password_confirm: "short"
    }

    assert user.reload.password_matches?("password123")
  end

  test "a guest cannot change a password" do
    create_user(username: "changer")

    post settings_password_path, params: {
      current_password: "password123",
      password: "newpassword456",
      password_confirm: "newpassword456"
    }

    assert_redirected_to login_path
  end
end