require "test_helper"

# The watched account is the member the simulated population reacts to. These
# tests pin what a post from that account actually does: the whole population is
# made due, a first slice answers inline, and the follower count climbs without
# a ceiling.
class SpotlightGrowthTest < ActiveSupport::TestCase
  setup do
    @watched = create_user(username: "watched", role: "owner")
    @watched.update_columns(bonus_followers: 0)

    # Point the simulation at this test's account and drop the engine's cached
    # lookup, otherwise it would still be watching the shipped default.
    SiteSetting.put(BotEngine::SPOTLIGHT_SETTING, "watched")
    BotEngine.reset_spotlight!

    @bots = 12.times.map do |i|
      bot = create_user(username: "growth_bot_#{i}", is_bot: true)
      bot.update_columns(next_action_at: 1.hour.from_now)
      bot
    end
  end

  def tweet_for(user, body = "hello world")
    user.tweets.create!(body: body)
  end

  test "the watched account is resolved by the configured name, case-insensitively" do
    SiteSetting.put(BotEngine::SPOTLIGHT_SETTING, "WATCHED")

    assert_equal @watched, BotEngine.watched_account
    assert BotEngine.watching?(@watched)
  end

  test "a post from the watched account makes the whole population due" do
    tweet = tweet_for(@watched)

    BotEngine.rally_to(tweet, inline: 0)

    due = @bots.count { |bot| bot.reload.next_action_at <= Time.current }
    assert_equal @bots.size, due, "every bot should be made due, not a sample"
  end

  test "the inline slice answers the post that was named" do
    tweet = tweet_for(@watched)

    performed = BotEngine.rally_to(tweet, inline: 5)

    assert_equal 5, performed
    # Everyone who acted aimed at this post rather than whatever was newest.
    engaged = @bots.count do |bot|
      TweetView.exists?(user_id: bot.id, tweet_id: tweet.id) ||
        Like.exists?(user_id: bot.id, tweet_id: tweet.id)
    end
    assert_equal 5, engaged
  end

  test "a post from an ordinary member does not rally the population" do
    other = create_user(username: "ordinary", role: "user")
    tweet = tweet_for(other)

    assert_equal 0, BotEngine.rally_to(tweet)
    assert @bots.all? { |bot| bot.reload.next_action_at > Time.current },
           "bots should keep their own schedule"
  end

  test "a post from the watched account brings followers with it" do
    tweet = tweet_for(@watched)

    BotEngine.rally_to(tweet, inline: 0)

    # The post grants GROWTH_PER_POST followers. Only 12 simulated accounts
    # exist, so those join for real and the rest are granted directly - the
    # total still reflects the full amount.
    assert_equal BotEngine::GROWTH_PER_POST, @watched.reload.follower_count
    assert_equal 12, @watched.followers.count
    assert_equal BotEngine::GROWTH_PER_POST - 12, @watched.bonus_followers
  end

  test "growth has no ceiling once the population already follows" do
    # Every bot already follows, so the only way to keep growing is to grant the
    # difference directly. This is what stops the count stalling at the
    # population size.
    @bots.each { |bot| Follow.create!(follower: bot, followee: @watched) }
    assert_equal @bots.size, @watched.reload.follower_count

    BotEngine.grow_followers(@watched, 50)

    assert_equal @bots.size + 50, @watched.reload.follower_count
    assert_equal 50, @watched.bonus_followers
  end

  test "granted followers are added to real ones rather than replacing them" do
    BotEngine.grow_followers(@watched, 100)

    # All 12 simulated accounts join for real; the remaining 88 are granted.
    assert_equal 12, @watched.followers.count
    assert_equal 88, @watched.reload.bonus_followers
    assert_equal 100, @watched.follower_count
  end

  test "growth is additive to followers that are already there" do
    Follow.create!(follower: @bots.first, followee: @watched)
    assert_equal 1, @watched.reload.follower_count

    BotEngine.grow_followers(@watched, 10)

    # The rate is what is gained, not a target total, so the existing follower
    # is kept and ten more are added on top.
    assert_equal 11, @watched.reload.follower_count
    assert_equal 0, @watched.bonus_followers
  end

  test "growth refuses to run for a simulated account" do
    bot = create_user(username: "selfish", is_bot: true, role: "user")

    assert_equal 0, BotEngine.grow_followers(bot, 10)
    assert_equal 0, bot.reload.follower_count
  end

  test "the per-tick rate can be switched off from settings" do
    SiteSetting.put(BotEngine::GROWTH_TICK_SETTING, "0")

    assert_equal 0, BotEngine.growth_per_tick
  end

  test "an unusable growth setting falls back to the default" do
    SiteSetting.put(BotEngine::GROWTH_TICK_SETTING, "not-a-number")

    assert_equal BotEngine::GROWTH_PER_TICK, BotEngine.growth_per_tick
  end

  test "a tick grows the audience while the watched account has posted recently" do
    tweet_for(@watched)
    before = @watched.reload.follower_count

    BotEngine.tick(count: 3)

    assert_operator @watched.reload.follower_count, :>, before
  end

  test "a tick does not grow the audience when the watched account is quiet" do
    before = @watched.reload.follower_count

    BotEngine.tick(count: 3)

    assert_equal before, @watched.reload.follower_count
  end

  test "replies to one post are capped so a thread stays readable" do
    tweet = tweet_for(@watched)
    # Fill the thread to the cap, then let the population answer again.
    BotEngine::REPLY_CAP_PER_TWEET.times do |i|
      @watched.tweets.create!(body: "reply #{i}", parent: tweet)
    end

    count_before = Tweet.where(parent_id: tweet.id).count
    # A bot whose roll lands in the reply band must like instead of replying.
    40.times { BotEngine.perform(@bots.first, focus: tweet) }

    assert_equal count_before, Tweet.where(parent_id: tweet.id).count,
                 "no further replies should be added past the cap"
  end
end
