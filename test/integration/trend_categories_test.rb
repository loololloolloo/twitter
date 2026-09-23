require "test_helper"

# 2019 labelled a trend with the vertical it belonged to ("Trending in
# Technology") above the tag itself. This build has no trend category table, so
# the label is derived from the tag text: a tag that names a known vertical is
# labelled, and a tag that matches nothing carries no label at all - a bare
# "Trending" would claim a vertical the data cannot back. These pin the mapping,
# the conservative matching, and that the label reaches every trend surface.
class TrendCategoriesTest < ActionDispatch::IntegrationTest
  # A tag only trends once three distinct accounts have used it.
  def make_trend(tag)
    base = SecureRandom.hex(3)
    3.times do |i|
      user = create_user(username: "u#{base}#{i}")
      Tweet.create!(user: user, body: "everyone is talking about ##{tag} today")
    end
  end

  test "a tag naming a vertical is labelled with that vertical" do
    assert_equal "Technology", Tweet.trend_category("rails")
    assert_equal "Technology", Tweet.trend_category("web3")
    assert_equal "Sports", Tweet.trend_category("nba")
    assert_equal "Entertainment", Tweet.trend_category("movie")
    assert_equal "News", Tweet.trend_category("election")
    assert_equal "Science", Tweet.trend_category("nasa")
    assert_equal "Business", Tweet.trend_category("stocks")
  end

  test "a tag with no known vertical is left unlabelled" do
    assert_nil Tweet.trend_category("vacationphotos")
    assert_nil Tweet.trend_category("hello")
    assert_nil Tweet.trend_category("")
  end

  test "a vertical is matched on whole words, not as a substring" do
    # "guardrails" must not read as rails, nor "marketeer" as market, or every
    # word that happens to embed a category name would be labelled after it.
    assert_nil Tweet.trend_category("guardrails")
    assert_nil Tweet.trend_category("marketeer")
    # A separator between the words still places the tag.
    assert_equal "Technology", Tweet.trend_category("ruby_on_rails")
  end

  test "compute_top_trends carries the category as the fourth element" do
    make_trend("steam_deck_rails")

    row = Tweet.compute_top_trends(8).find { |tag, _, _, _| tag == "steam_deck_rails" }
    assert row, "the trend was not computed"
    assert_equal 4, row.size
    assert_equal "Technology", row[3], "the tag did not carry its vertical"
  end

  test "the right rail labels a categorised trend and leaves others bare" do
    me = create_user(username: "trend_rail_me")
    sign_in(me)
    make_trend("javascript")
    make_trend("gibberishhshs")

    get home_path
    assert_response :success

    assert_match(%r{Trending in Technology.*#javascript}m, response.body,
                 "the rail did not label a categorised trend")
    assert_no_match(%r{Trending in \w+.*#gibberishhshs}m, response.body,
                    "an unplaced tag was given a vertical it does not have")
  end

  test "the Explore screen labels trends too" do
    me = create_user(username: "expl_trend_me")
    sign_in(me)
    make_trend("basketball")

    get explore_path
    assert_response :success
    assert_match(%r{Trending in Sports.*#basketball}m, response.body,
                 "Explore did not label a categorised trend")
  end
end
