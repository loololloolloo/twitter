require "test_helper"

# The first account is special: it owns the instance. These tests drive the
# real signup form rather than building users directly, because that ordering
# rule only lives in the controller.
class SignupOwnershipTest < ActionDispatch::IntegrationTest
  test "the first signup becomes the owner with every permission" do
    assert_equal 0, User.count

    post signup_path, params: {
      username: "founder", display_name: "The Founder",
      email: "founder@example.com",
      password: "password123", password_confirm: "password123"
    }

    assert_redirected_to home_path
    founder = User.find_by!(username: "founder")
    assert_equal Role::OWNER, founder.role.name
    assert_equal Permission.count, founder.permission_keys.size
    assert founder.owner?
    assert founder.can?("admin.access")
    assert founder.can?("users.followers")
  end

  test "later signups become regular members" do
    create_user(username: "founder", role: "owner")

    post signup_path, params: {
      username: "second", display_name: "Second",
      email: "second@example.com",
      password: "password123", password_confirm: "password123"
    }

    assert_equal "user", User.find_by!(username: "second").role.name
  end

  test "signup is refused when registration is closed" do
    SiteSetting.put("registration_open", "0")

    post signup_path, params: {
      username: "late", display_name: "Late", email: "late@example.com",
      password: "password123", password_confirm: "password123"
    }

    assert_response :forbidden
    refute User.exists?(username: "late")
  end

  test "mismatched passwords are rejected" do
    post signup_path, params: {
      username: "clumsy", display_name: "Clumsy", email: "clumsy@example.com",
      password: "password123", password_confirm: "password124"
    }

    assert_response :unprocessable_entity
    refute User.exists?(username: "clumsy")
  end

  test "a short password is rejected" do
    post signup_path, params: {
      username: "shorty", display_name: "Shorty", email: "shorty@example.com",
      password: "short", password_confirm: "short"
    }

    assert_response :unprocessable_entity
    refute User.exists?(username: "shorty")
  end

  test "no placeholder users exist after bootstrapping" do
    RoleBootstrapper.run
    assert_equal 0, User.count
  end
end