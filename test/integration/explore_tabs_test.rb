require "test_helper"

# 2019's Explore screen and its search screen shared a URL but not their tabs:
# Explore landed on For you, Trending, News, Sports, Entertainment, while a
# query produced Top, Latest, People, Photos, Videos. These pin both strips and
# the rule that only one is ever shown, since rendering the wrong one leaves a
# tab on screen that leads nowhere.
class ExploreTabsTest < ActionDispatch::IntegrationTest
  setup do
    @me = create_user(username: "explore_me")
    @other = create_user(username: "explore_other")
    sign_in @me
  end

  LANDING = [ "For you", "Trending", "News", "Sports", "Entertainment" ].freeze
  SEARCH  = %w[Top Latest People Photos Videos].freeze

  # The tab strip as labels, so an assertion does not depend on how the markup
  # is indented or whether a label also appears in the page body.
  def tab_labels(body)
    strip = body[%r{<ul class="profile-tabs">(.*?)</ul>}m, 1]
    return [] if strip.nil?

    strip.scan(%r{<li[^>]*>(.*?)</li>}m).flatten.map { |item| strip_tags(item).strip }
  end

  def active_tab(body)
    item = body[%r{<li class="pt-item is-active">(.*?)</li>}m, 1]
    item && strip_tags(item).strip
  end

  def strip_tags(html)
    html.gsub(%r{<[^>]+>}, "")
  end

  test "the Explore landing screen offers the five 2019 sections" do
    get explore_path
    assert_response :success

    assert_equal LANDING, tab_labels(response.body)
    assert_equal "For you", active_tab(response.body)
    assert_match(%r{href="/explore\?tab=trending"}, response.body)
    assert_match(%r{href="/explore\?tab=news"}, response.body)
    assert_match(%r{href="/explore\?tab=sports"}, response.body)
    assert_match(%r{href="/explore\?tab=entertainment"}, response.body)
  end

  test "each Explore section is reachable and marked active" do
    { "for-you" => "For you", "trending" => "Trending", "news" => "News",
      "sports" => "Sports", "entertainment" => "Entertainment" }.each do |key, label|
      get explore_path(tab: key)
      assert_response :success
      assert_equal label, active_tab(response.body), "#{label} should be the active section"
      assert_equal LANDING, tab_labels(response.body), "the strip should not change per section"
    end
  end

  test "the Explore landing screen does not offer search result tabs" do
    get explore_path
    assert_response :success

    assert_empty(tab_labels(response.body) & SEARCH,
                 "the landing screen should offer only Explore sections")
  end

  test "a search keeps its five result tabs" do
    get explore_path(q: "explore")
    assert_response :success

    assert_equal SEARCH, tab_labels(response.body)
    assert_empty(tab_labels(response.body) & LANDING,
                 "a search should offer only result tabs")
  end

  test "a section name is not reachable as a search tab and vice versa" do
    # A query at "Photos" would be a result tab on the landing screen; the two
    # name sets must not leak into each other.
    get explore_path(tab: "photos")
    assert_response :success
    assert_equal "For you", active_tab(response.body),
                 "an unknown landing section should fall back to For you"

    get explore_path(q: "x", tab: "trending")
    assert_response :success
    assert_equal "Top", active_tab(response.body),
                 "an unknown search tab should fall back to Top"
  end

  test "For you prefers the accounts the reader follows" do
    followed = create_user(username: "exp_followed")
    Follow.create!(follower: @me, followee: followed)
    Tweet.create!(user: followed, body: "from someone you follow")
    Tweet.create!(user: @other, body: "from a stranger")

    get explore_path(tab: "for-you")
    assert_response :success
    assert_match "from someone you follow", response.body
    assert_no_match(/from a stranger/, response.body,
                    "For you should not surface an unfollowed account's post")
  end

  test "For you falls back to the site stream when nothing is followed" do
    Tweet.create!(user: @other, body: "a lonely post")

    get explore_path(tab: "for-you")
    assert_response :success
    assert_match "a lonely post", response.body,
                 "an account following nobody should still see something"
  end

  test "Trending gathers posts carrying a trend tag" do
    # A tag needs three distinct authors to count as a trend.
    authors = 3.times.map { |i| create_user(username: "exp_tr_#{i}") }
    authors.each { |a| Follow.create!(follower: @me, followee: a) }
    authors.each { |a| Tweet.create!(user: a, body: "talking about #exploretrend now") }
    Tweet.create!(user: @other, body: "unrelated chatter")

    get explore_path(tab: "trending")
    assert_response :success
    assert_match "#exploretrend", response.body
    assert_no_match(/unrelated chatter/, response.body,
                    "Trending should only carry tagged posts")
  end

  test "Trending tags are matched as hashtags rather than as bare words" do
    authors = 3.times.map { |i| create_user(username: "exp_ba_#{i}") }
    authors.each { |a| Follow.create!(follower: @me, followee: a) }
    authors.each { |a| Tweet.create!(user: a, body: "discussing #railtag here") }
    # "guardrails" contains "rails" but is not the #railtag hashtag.
    Tweet.create!(user: @other, body: "guardrails are unrelated entirely")

    get explore_path(tab: "trending")
    assert_response :success
    assert_match "#railtag", response.body
    assert_no_match(/guardrails are unrelated/, response.body)
  end

  test "a vertical section matches its own subject" do
    Tweet.create!(user: @other, body: "the team won the final match")

    get explore_path(tab: "sports")
    assert_response :success
    assert_match "the team won the final match", response.body
  end

  test "an unrecognised section or tab falls back rather than erroring" do
    assert_equal 200, status_for(explore_path(tab: "haxxor"))
    assert_equal 200, status_for(explore_path(q: "x", tab: "haxxor"))
  end

  private

  def status_for(path)
    get path
    response.status
  end
end