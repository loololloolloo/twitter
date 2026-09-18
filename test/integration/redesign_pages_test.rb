require "test_helper"

# Every page the 2019 redesign added or reworked renders inside the shared
# shell. A controller test would not catch a template that raises halfway down
# the page, so these assert the full render, and assert the marker that says
# which piece of the redesign the page is supposed to be showing.
class RedesignPagesTest < ActionDispatch::IntegrationTest
  setup do
    @me = create_user(username: "design_me")
    @other = create_user(username: "design_other")
    @tweet = Tweet.create!(user: @other, body: "redesign body")

    sign_in @me
  end

  def assert_renders(path, marker)
    get path
    assert_response :success, "#{path} did not render cleanly"
    assert_match marker, response.body, "#{path} is missing its #{marker.inspect} marker"
    assert_match "side-nav", response.body, "#{path} did not render inside the app shell"
  end

  test "the home and explore streams render" do
    assert_renders home_path, "redesign body"
    assert_renders explore_path, "redesign body"
  end

  # The 2019 search screen carried Top, Latest, People and Photos as tabs over
  # one query. The controller computed the tab but the view never offered a way
  # to reach it, so the strip is asserted here.
  test "a search offers the four 2019 result tabs" do
    get explore_path(q: "redesign")
    assert_response :success
    assert_match "profile-tabs", response.body

    %w[Top Latest People Photos].each { |label| assert_match(/#{label}/, response.body) }
    assert_match(%r{href="/explore\?[^"]*tab=latest}, response.body)
    assert_match(%r{href="/explore\?[^"]*tab=photos}, response.body)

    get explore_path(q: "redesign", tab: "photos")
    assert_response :success
    assert_match "pt-item is-active", response.body
  end

  test "the permalink renders with its action row" do
    assert_renders tweet_path(@tweet), "tweet-actions"
  end

  test "the profile renders with its banner and picture" do
    assert_renders profile_path(@other.username), "profile-canopy"
  end

  test "the notifications page renders with its tabs" do
    assert_renders notifications_path, "profile-tabs"
  end

  test "the new feature pages render" do
    assert_renders bookmarks_path, "Bookmarks"
    assert_renders lists_path, "Lists"
    assert_renders follow_requests_path, "Follow requests"
  end

  test "the settings pages render for each panel" do
    %w[account security privacy notifications accessibility data].each do |panel|
      assert_renders settings_path(panel: panel), "settings-nav"
    end
  end

  test "the report form renders for a post" do
    assert_renders new_report_path(tweet_id: @tweet.id), "report-reasons"
  end

  test "the composer carries the alt-text field" do
    get home_path
    assert_response :success
    assert_match "data-alt-wrap", response.body
    assert_match "Describe this image", response.body
  end

  test "a quote tweet renders both bodies in the stream" do
    Tweet.create!(user: @me, body: "quoting redesign", quote_of_id: @tweet.id)

    get home_path
    assert_response :success
    assert_match "quoting redesign", response.body
    assert_match "redesign body", response.body
    assert_match "quote-card", response.body
  end

  test "a locked profile renders the notice instead of a stream" do
    @other.update!(protected: true)

    get profile_path(@other.username)
    assert_response :success
    assert_match "lock-notice", response.body
    assert_no_match "redesign body", response.body
  end

  test "the 404 screen renders without the debug router" do
    get "/definitely-not-a-real-page"

    assert_response :not_found
    assert_match "That page does not exist", response.body
    assert_no_match "routes are displayed", response.body
    assert_no_match "Routing Error", response.body
  end

  # A record that is missing or unreadable is a 404 too, and it has to answer
  # with the app's own screen. These paths used to return a bare "Not found"
  # line, which left the reader on a page with no way back.
  test "a missing record answers with the app's own 404 screen" do
    user = create_user(username: "missing_reader")
    sign_in(user)

    [ tweet_path(999_999_999), profile_path("nobody_here_at_all"), page_path("no-such-page") ].each do |path|
      get path
      assert_response :not_found, "#{path} did not answer 404"
      assert_match "error-page", response.body, "#{path} did not render the error screen"
      assert_no_match "Routing Error", response.body
    end
  end
end
