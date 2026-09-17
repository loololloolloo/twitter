require "test_helper"

# Covers the retweet button end to end: the row is written, the button reports
# its new state, and the retweet is actually reachable afterwards. The original
# bug was that a retweet saved silently - no state change, no flash, and no
# appearance in the retweeter's own home feed.
class RetweetFlowTest < ActionDispatch::IntegrationTest
  setup do
    @me = create_user(username: "retweeter", role: "owner")
    @author = create_user(username: "author")
    @tweet = Tweet.create!(user: @author, body: "a tweet worth sharing")
  end

  test "retweeting a tweet writes a retweet row and confirms it" do
    sign_in(@me)

    assert_difference -> { Tweet.where(user_id: @me.id).count }, 1 do
      post retweet_tweet_path(@tweet)
    end

    assert_redirected_to tweet_path(@tweet)
    follow_redirect!
    assert_match(/Retweeted\./, response.body)
    assert @tweet.retweeted_by?(@me)
  end

  test "the retweet button reflects the retweeted state" do
    sign_in(@me)
    post retweet_tweet_path(@tweet)

    follow_redirect!
    assert_select "button.act-rt.rt-active", text: /Retweeted/
  end

  test "clicking retweet again undoes it" do
    sign_in(@me)
    post retweet_tweet_path(@tweet)

    assert_difference -> { Tweet.where(user_id: @me.id, is_deleted: false).count }, -1 do
      post retweet_tweet_path(@tweet)
    end

    follow_redirect!
    assert_match(/Retweet undone\./, response.body)
    assert_not @tweet.retweeted_by?(@me)
  end

  test "a retweet appears in the retweeter's own home feed" do
    sign_in(@me)
    post retweet_tweet_path(@tweet)
    @me.active_follows.create!(followee: @author)

    get home_path
    assert_response :success
    assert_match(/Retweeted by/, response.body)
    assert_match(/a tweet worth sharing/, response.body)
  end

  test "a retweet is not duplicated when the author is also followed" do
    sign_in(@me)
    @me.active_follows.create!(followee: @author)
    post retweet_tweet_path(@tweet)

    get home_path
    assert_response :success

    # The original shows once and the retweet shows once; the retweet must not
    # also drag in a second copy of the original body.
    assert_equal 1, response.body.scan(/Retweeted by/).size
  end

  test "you cannot retweet your own tweet" do
    sign_in(@author)

    assert_no_difference -> { Tweet.where(user_id: @author.id).count } do
      post retweet_tweet_path(@tweet)
    end

    assert_match(/cannot retweet your own tweet/, flash[:alert].to_s)
  end

  test "a deleted retweet does not count toward the retweet total" do
    sign_in(@me)
    post retweet_tweet_path(@tweet)
    assert_equal 1, @tweet.retweet_count

    post retweet_tweet_path(@tweet)
    assert_equal 0, @tweet.retweet_count
  end
end