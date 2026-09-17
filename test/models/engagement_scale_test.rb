require "test_helper"

# A post's displayed engagement is not limited by how many accounts exist. Only
# a few thousand simulated accounts are on the site, so the counts a popular
# post shows have no row behind most of them; the bonus columns carry that part
# and the real reactions are added on top. These tests pin both halves, because
# a count that ignored either would be wrong in a way that is easy to miss.
class EngagementScaleTest < ActiveSupport::TestCase
  setup do
    @author = create_user(username: "author")
    @bot = create_user(username: "liker", is_bot: true)
    @tweet = @author.tweets.create!(body: "a post worth reacting to")
  end

  test "a fresh post starts at zero" do
    assert_equal 0, @tweet.like_count
    assert_equal 0, @tweet.favourite_count
    assert_equal 0, @tweet.retweet_count
  end

  test "a granted count is reported alongside the reactions that have rows" do
    @tweet.update_columns(bonus_likes: 4_000)
    Like.create!(user: @bot, tweet: @tweet, kind: Like::LIKE)

    assert_equal 4_001, @tweet.reload.like_count,
                 "the granted part and the real reaction should both count"
  end

  test "the three counters are granted independently" do
    @tweet.update_columns(bonus_likes: 880, bonus_favourites: 35, bonus_retweets: 85)

    @tweet.reload
    assert_equal 880, @tweet.like_count
    assert_equal 35, @tweet.favourite_count
    assert_equal 85, @tweet.retweet_count
  end

  test "a reaction from one account moves a large count by one" do
    @tweet.update_columns(bonus_likes: 100_000)
    before = @tweet.reload.like_count

    Like.create!(user: @bot, tweet: @tweet, kind: Like::LIKE)

    assert_equal before + 1, @tweet.reload.like_count
  end

  test "a retweet is added to the granted total" do
    @tweet.update_columns(bonus_retweets: 500)
    @bot.tweets.create!(body: "", retweet_of: @tweet)

    assert_equal 501, @tweet.reload.retweet_count
  end

  test "a deleted retweet does not count" do
    @tweet.update_columns(bonus_retweets: 500)
    retweet = @bot.tweets.create!(body: "", retweet_of: @tweet)
    retweet.update_columns(is_deleted: true)

    assert_equal 500, @tweet.reload.retweet_count
  end

  test "a reply is counted from its row" do
    @bot.tweets.create!(body: "replying", parent: @tweet)

    assert_equal 1, @tweet.reload.reply_count
  end

  # The engine's own helper, which is what actually raises counts on a running
  # site.

  test "a bump is split across the counters in the engine's shares" do
    BotEngine.bump_engagement(@tweet, cut: 1_000)

    @tweet.reload
    assert_equal 880, @tweet.like_count
    assert_equal 35, @tweet.favourite_count
    assert_equal 85, @tweet.retweet_count
    assert_equal 1_000, @tweet.like_count + @tweet.favourite_count + @tweet.retweet_count
  end

  test "bumps accumulate rather than replacing the current figure" do
    BotEngine.bump_engagement(@tweet, cut: 1_000)
    BotEngine.bump_engagement(@tweet, cut: 1_000)

    @tweet.reload
    assert_equal 2_000, @tweet.like_count + @tweet.favourite_count + @tweet.retweet_count
  end

  test "a bump with nothing to add leaves the post untouched" do
    @tweet.update_columns(bonus_likes: 7)

    assert_no_changes -> { @tweet.reload.bonus_likes } do
      BotEngine.bump_engagement(@tweet, reads: 0, cut: 0)
    end
  end

  test "a bump with no post is harmless" do
    assert_nil BotEngine.bump_engagement(nil, reads: 5)
  end

  test "an ordinary post still shows a small, plausible number" do
    assert_equal 0, @tweet.reload.like_count

    Like.create!(user: @bot, tweet: @tweet, kind: Like::LIKE)
    assert_equal 1, @tweet.reload.like_count
  end

  # The seeder's distribution, which is what makes a live site show a spread
  # rather than a plateau.

  test "a member's post is never left with a trivial tail" do
    human = create_user(username: "real_person")
    tail = BotSeeder.engagement_tail(human.id, Set.new([ human.id ]))

    assert_operator tail, :>=, BotSeeder::MEMBER_TAIL_FLOOR
  end

  test "a bot's post is usually left ordinary" do
    bot = create_user(username: "seed_bot", is_bot: true)
    tails = 400.times.map { BotSeeder.engagement_tail(bot.id, Set.new) }

    assert_operator tails.count(&:zero?), :>, tails.size / 2,
                    "most seeded posts should be ordinary, not viral"
    assert_operator tails.count(&:positive?), :>, 0,
                    "some posts should carry a tail"
  end

  test "the tail spans orders of magnitude rather than clustering" do
    values = 500.times.map { BotSeeder.log_uniform(BotSeeder::VIRAL_RANGE) }

    assert_operator values.max / values.min.to_f, :>, 50,
                    "the spread should cover several orders of magnitude"
  end

  test "the tail stays inside the configured range" do
    values = 500.times.map { BotSeeder.log_uniform(BotSeeder::VIRAL_RANGE) }

    assert(values.all? { |v| v.between?(BotSeeder::VIRAL_RANGE.first, BotSeeder::VIRAL_RANGE.last) })
  end

  test "the tail can exceed the population, which no row count could" do
    assert_operator BotSeeder::VIRAL_RANGE.last, :>, User.count
    assert_operator BotSeeder::VIRAL_RANGE.last, :>=, 100_000
  end
end