ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Parallel workers get their own database, so ids repeat across them, but
    # public/uploads is a single directory on disk. Two workers uploading an
    # avatar for their own "user 1" would write into the same directory and the
    # cleanup in one would delete the other's file. Giving each worker its own
    # upload root keeps the filesystem as isolated as the database.
    parallelize_setup do |worker|
      Uploads.send(:remove_const, :ROOT)
      Uploads.const_set(:ROOT, Rails.root.join("public", "uploads", "test-#{worker}"))
    end

    parallelize_teardown do |worker|
      FileUtils.rm_rf(Rails.root.join("public", "uploads", "test-#{worker}"))
    end

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Every test starts from the same role ladder and permission registry that
    # `rails db:seed` installs, so signup, admin gating and role ranks behave
    # the way they do on a real install.
    setup do
      RoleBootstrapper.run
    end

    # Builds a user directly, bypassing the signup form.
    def create_user(username:, role: "user", password: "password123", **attrs)
      User.create!(
        username: username,
        display_name: attrs.delete(:display_name) || username.capitalize,
        email: attrs.delete(:email) || "#{username}@example.com",
        password_hash: PasswordDigest.hash(password),
        role: Role.find_by!(name: role),
        **attrs
      )
    end

    # Puts a user's id in the test session, which is how the app tracks login.
    def sign_in(user)
      post login_path, params: { identifier: user.username, password: "password123" }
      assert_response :redirect, "sign in for @#{user.username} did not succeed"
    end

    def sign_in_with(password:, identifier:)
      post login_path, params: { identifier: identifier, password: password }
    end
  end
end
