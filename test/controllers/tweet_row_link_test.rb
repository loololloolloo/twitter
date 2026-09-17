require "test_helper"

# A tweet row is a permalink target: clicking it opens the tweet's own page.
# That is delivered as an overlay anchor spanning the row, which must point at
# the tweet whose body is shown - for a retweet that is the original, not the
# retweet row itself.
class TweetRowLinkTest < ActionDispatch::IntegrationTest
  setup do
    @me = create_user(username: "rowreader", role: "owner")
    @author = create_user(username: "rowauthor")
    @me.active_follows.create!(followee: @author)
    sign_in(@me)
  end

  test "each timeline row carries a full-row link to its tweet" do
    tweet = Tweet.create!(user: @author, body: "clickable row")

    get home_path
    assert_response :success

    assert_select "li.tweet[data-tweet='#{tweet.id}'] a.tweet-open[href='#{tweet_path(tweet)}']" do |links|
      assert_equal 1, links.size
    end
  end

  test "a retweet row links to the original tweet" do
    original = Tweet.create!(user: @author, body: "the original body")
    Tweet.create!(user: @me, body: "", retweet_of: original)

    get home_path
    assert_response :success

    assert_select "a.tweet-open[href='#{tweet_path(original)}']"
    assert_select "a.tweet-open[href='#{tweet_path(original)}']", minimum: 1
  end

  test "the tweet page still renders the focused tweet" do
    tweet = Tweet.create!(user: @author, body: "read me")

    get tweet_path(tweet)
    assert_response :success
    assert_select "article.permalink-tweet", text: /read me/
  end
end