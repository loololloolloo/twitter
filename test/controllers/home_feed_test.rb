require "test_helper"

# The home timeline refreshes itself by polling /home/feed with the newest
# timestamp it already has. Two bugs lived here: the cursor was serialised at
# second precision, so the newest tweet always compared as newer than itself
# and was re-sent on every poll; and the client re-queued rows it had already
# shown, so pressing "new tweets" duplicated what was below.
class HomeFeedTest < ActionDispatch::IntegrationTest
  setup do
    @me = create_user(username: "feedreader", role: "owner")
    @author = create_user(username: "feedauthor")
    @me.active_follows.create!(followee: @author)
    sign_in(@me)
  end

  test "the cursor keeps sub-second precision" do
    tweet = Tweet.create!(user: @author, body: "precise timestamp")

    get home_path
    assert_response :success

    cursor = response.body[/data-newest="([^"]*)"/, 1]
    assert cursor.present?, "the timeline did not expose a feed cursor"

    # Round-tripping the cursor must land exactly on the tweet, not before it.
    assert_equal tweet.created_at.to_i, Time.zone.parse(cursor).to_i
    assert_equal tweet.created_at.usec, Time.zone.parse(cursor).usec
  end

  test "polling with the page cursor does not repeat the newest tweet" do
    Tweet.create!(user: @author, body: "already on the page")

    get home_path
    cursor = response.body[/data-newest="([^"]*)"/, 1]

    get home_feed_path(after: cursor)
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal 0, body["count"], "the newest tweet was re-sent on the first poll"
    assert_no_match(/data-tweet/, body["html"])
  end

  test "a tweet posted after the page loaded is served exactly once" do
    get home_path
    cursor = response.body[/data-newest="([^"]*)"/, 1]

    Tweet.create!(user: @author, body: "brand new arrival")

    get home_feed_path(after: cursor)
    body = JSON.parse(response.body)
    assert_equal 1, body["count"]
    assert_match(/brand new arrival/, body["html"])

    # The client advances to the returned cursor, so the next poll is empty.
    get home_feed_path(after: body["newest"])
    assert_equal 0, JSON.parse(response.body)["count"]
  end

  test "a malformed cursor falls back to the latest entries rather than erroring" do
    Tweet.create!(user: @author, body: "still served")

    get home_feed_path(after: "not-a-time")
    assert_response :success
    assert_equal 0, JSON.parse(response.body)["count"]
  end
end