require "test_helper"

# The engagement controls update in place rather than reloading the page, so
# they answer with the tweet's new state. These tests cover the JSON contract
# the page relies on: a toggle has to report the new counts and whether the
# action is on, or the button repaints wrongly.
class TweetActionToggleTest < ActionDispatch::IntegrationTest
  setup do
    @me = create_user(username: "toggler", role: "owner")
    @author = create_user(username: "poster")
    @tweet = Tweet.create!(user: @author, body: "a tweet to react to")
  end

  test "liking a tweet answers with the new like state" do
    sign_in(@me)

    assert_difference -> { @tweet.likes.count }, 1 do
      post like_tweet_path(@tweet), as: :json
    end

    body = JSON.parse(response.body)
    assert_equal @tweet.id, body["id"]
    assert_equal true, body["liked"]
    assert_equal 1, body["like_count"]
    assert_equal "1", body["like_count_label"]
    assert_equal false, body["retweeted"]
  end

  test "unliking a tweet answers with the like removed" do
    sign_in(@me)
    Like.create!(user: @me, tweet: @tweet)

    assert_difference -> { @tweet.likes.count }, -1 do
      delete like_tweet_path(@tweet), as: :json
    end

    body = JSON.parse(response.body)
    assert_equal false, body["liked"]
    assert_equal 0, body["like_count"]
  end

  test "retweeting answers with the retweeted state" do
    sign_in(@me)

    assert_difference -> { Tweet.where(user_id: @me.id, retweet_of_id: @tweet.id).count }, 1 do
      post retweet_tweet_path(@tweet), as: :json
    end

    body = JSON.parse(response.body)
    assert_equal true, body["retweeted"]
    assert_equal 1, body["retweet_count"]
    assert_equal false, body["liked"]
  end

  test "retweeting again toggles the retweet off" do
    sign_in(@me)
    post retweet_tweet_path(@tweet), as: :json

    assert_difference -> { @tweet.retweet_count }, -1 do
      post retweet_tweet_path(@tweet), as: :json
    end

    body = JSON.parse(response.body)
    assert_equal false, body["retweeted"]
    assert_equal 0, body["retweet_count"]
  end

  test "a retweet response carries the like state so the star is not cleared" do
    sign_in(@me)
    Like.create!(user: @me, tweet: @tweet)

    post retweet_tweet_path(@tweet), as: :json

    body = JSON.parse(response.body)
    assert_equal true, body["liked"], "a retweet must not report the tweet as unliked"
    assert_equal 1, body["like_count"]
  end

  test "retweeting your own tweet is refused with an error" do
    mine = Tweet.create!(user: @me, body: "my own tweet")
    sign_in(@me)

    post retweet_tweet_path(mine), as: :json

    assert_response :unprocessable_entity
    assert_equal "You cannot retweet your own tweet.", JSON.parse(response.body)["error"]
  end

  test "the plain form submit still redirects when JSON is not requested" do
    sign_in(@me)

    post like_tweet_path(@tweet)

    assert_response :redirect
    assert_equal 1, @tweet.likes.count
  end

  test "favouriting a tweet does not like it" do
    sign_in(@me)

    assert_difference -> { @tweet.favourite_count }, 1 do
      post favorite_tweet_path(@tweet), as: :json
    end

    body = JSON.parse(response.body)
    assert_equal true, body["favourited"]
    assert_equal false, body["liked"], "starring a post must not mark it liked"
    assert_equal 0, body["like_count"]
    assert_equal 1, body["favourite_count"]
  end

  test "liking a tweet does not favourite it" do
    sign_in(@me)

    post like_tweet_path(@tweet), as: :json

    body = JSON.parse(response.body)
    assert_equal true, body["liked"]
    assert_equal false, body["favourited"], "liking a post must not mark it favourited"
    assert_equal 0, body["favourite_count"]
  end

  test "a tweet can be both favourited and liked" do
    sign_in(@me)

    post favorite_tweet_path(@tweet), as: :json
    post like_tweet_path(@tweet), as: :json

    body = JSON.parse(response.body)
    assert_equal true, body["favourited"]
    assert_equal true, body["liked"]
    assert_equal 1, @tweet.favourite_count
    assert_equal 1, @tweet.like_count
  end

  test "unfavouriting leaves the like in place" do
    sign_in(@me)
    post favorite_tweet_path(@tweet), as: :json
    post like_tweet_path(@tweet), as: :json

    delete favorite_tweet_path(@tweet), as: :json

    body = JSON.parse(response.body)
    assert_equal false, body["favourited"]
    assert_equal true, body["liked"], "removing the star must not remove the heart"
    assert_equal 1, body["like_count"]
  end

  test "each reaction notifies the author under its own kind" do
    sign_in(@me)

    post favorite_tweet_path(@tweet), as: :json
    post like_tweet_path(@tweet), as: :json

    kinds = @author.notifications.pluck(:kind)
    assert_includes kinds, "favourite"
    assert_includes kinds, "like"
  end
end
