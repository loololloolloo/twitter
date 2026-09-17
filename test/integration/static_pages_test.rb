require "test_helper"

# The four footer pages and the error screens. These are the dead links that
# used to 404, so each one is requested for real.
class StaticPagesTest < ActionDispatch::IntegrationTest
  test "footer pages render for a signed-in user" do
    user = create_user(username: "reader")
    sign_in(user)

    {
      about_path => /classic web client/i,
      help_path => /Tweets are limited to/i,
      tos_path => /Terms of Service/i,
      privacy_path => /Privacy Policy/i
    }.each do |path, pattern|
      get path
      assert_response :success, "#{path} did not render"
      assert_match pattern, response.body
    end
  end

  test "the footer links point at pages that exist" do
    user = create_user(username: "reader")
    sign_in(user)
    get home_path

    %w[/about /help /tos /privacy].each do |href|
      assert_match(/href="#{href}"/, response.body, "footer is missing #{href}")
    end
  end

  test "an unknown page slug is a 404" do
    user = create_user(username: "reader")
    sign_in(user)

    get "/pages/nonsense"
    assert_response :not_found
  end

  test "the error screens render with their status codes" do
    user = create_user(username: "reader")
    sign_in(user)

    {
      not_found_path => [ 404, /That page does not exist/ ],
      forbidden_path => [ 403, /do not have permission/ ]
    }.each do |path, (code, pattern)|
      get path
      assert_response code
      assert_match pattern, response.body
      # The error screen uses the app's own layout, not a bare static page.
      assert_match(/site-footer/, response.body)
    end
  end
end