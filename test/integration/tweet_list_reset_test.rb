require "test_helper"

# Bookmarks, a List timeline and Quote Tweets each render the shared tweet
# partial inside `<ul class="tweet-list">`. Unlike the primary streams, which
# use `.timeline`, that list had no stylesheet rule at all, so the browser's
# default bullet and indent survived and the rows did not sit flush like the
# 2019 web client. The markup cannot show it in a response - the failure lives
# in the stylesheet - so the reset is asserted directly.
class TweetListResetTest < ActionDispatch::IntegrationTest
  STYLESHEETS = %w[twitter.css twitter-2015.css twitter-prototype.css].freeze

  setup do
    @alice = create_user(username: "alice")
    @bob = create_user(username: "bob")
  end

  test "every timeline stylesheet resets the tweet-list bullets and indent" do
    STYLESHEETS.each do |name|
      css = Rails.root.join("app/assets/stylesheets", name).read

      assert_match(/\.timeline\s*,\s*\.tweet-list\s*\{[^}]*list-style:\s*none/m, css,
                   "#{name} leaves the browser bullets on .tweet-list")
      assert_match(/\.timeline\s*,\s*\.tweet-list\s*\{[^}]*margin:\s*0/m, css,
                   "#{name} leaves the browser indent on .tweet-list")
      assert_match(/\.timeline\s*,\s*\.tweet-list\s*\{[^}]*padding:\s*0/m, css,
                   "#{name} leaves the browser padding on .tweet-list")
    end
  end

  test "bookmarks, a list timeline and quotes render in the reset list" do
    tweet = Tweet.create!(user: @bob, body: "quotable post")
    @alice.bookmarks.create!(tweet: tweet)
    list = List.create!(user: @alice, name: "Reading")
    list.list_memberships.create!(user: @bob)

    sign_in @alice

    get bookmarks_path
    assert_response :success
    assert_select "ul.tweet-list"

    get list_path(list)
    assert_response :success
    assert_select "ul.tweet-list"

    get tweet_quotes_path(tweet)
    assert_response :success
    assert_select "ul.tweet-list"
  end
end
