require "test_helper"

# A site where the simulated population only reacts to itself is not what the
# simulation is for: the real members have to be among the accounts that get
# attention, and that attention has to be shared out rather than all landing on
# whichever member posted most recently. These tests pin both.
class HumanEngagementTest < ActiveSupport::TestCase
  setup do
    @bots = 20.times.map do |i|
      bot = create_user(username: "engage_bot_#{i}", is_bot: true,
                        persona: PersonaGenerator.build(i + 100).to_json)
      # Out of the way of `tick`, so these tests drive single bots directly.
      bot.update_columns(next_action_at: 1.hour.from_now)
      bot
    end
  end

  # The candidate pool is what a bot's next like or reply is drawn from. It used
  # to be the newest posts by anyone, which on a busy site is almost entirely
  # simulated accounts - the newest member's post fell off the end long before
  # any bot reached it.

  test "the candidate pool reaches a member's posts" do
    member = create_user(username: "real_member")
    ours = member.tweets.create!(body: "something worth answering")
    # A crowd of simulated posts, which is what buries a member's post when the
    # pool is a plain recency slice.
    60.times { |i| @bots.first.tweets.create!(body: "bot chatter #{i}") }

    pool = BotEngine.send(:engagement_pool, @bots.last)

    assert_includes pool.map(&:id), ours.id,
                    "a member's post should be reachable from the pool"
  end

  test "the pool still holds ordinary posts alongside the members'" do
    member = create_user(username: "real_member2")
    member.tweets.create!(body: "member post")
    bot_post = @bots.first.tweets.create!(body: "bot post")

    pool = BotEngine.send(:engagement_pool, @bots.last)

    assert_includes pool.map(&:id), bot_post.id
  end

  test "a member's post kept off the pool by age is dropped" do
    member = create_user(username: "quiet_member")
    old = member.tweets.create!(body: "from ages ago")
    old.update_columns(created_at: (BotEngine::HUMAN_ENGAGEMENT_WINDOW + 1.day).ago)
    # Enough newer simulated posts to fill the general arm, so the old member
    # post survives only if the window is ignored.
    BotEngine::CANDIDATE_POOL.times { |i| @bots.first.tweets.create!(body: "filler #{i}") }

    pool = BotEngine.send(:engagement_pool, @bots.last)

    refute_includes pool.map(&:id), old.id
  end

  test "a member's post is never offered to its own author" do
    member = create_user(username: "self_member")
    own = member.tweets.create!(body: "my own post")

    pool = BotEngine.send(:engagement_pool, member)

    refute_includes pool.map(&:id), own.id
  end

  test "the pool does not list a member's post twice" do
    member = create_user(username: "once_member")
    theirs = member.tweets.create!(body: "member post")
    # The general arm takes the newest posts, which includes this one, and the
    # member arm asks for it again by name.
    @bots.first.tweets.create!(body: "a bot post")

    pool = BotEngine.send(:engagement_pool, @bots.last)
    ids = pool.map(&:id)

    assert_equal ids.uniq.sort, ids.sort, "a post should appear once in the pool"
    assert_equal 1, ids.count(theirs.id)
  end

  # The spotlight is who the population is currently reacting to. It used to be
  # taken as the single most active member, which meant one account collected
  # everything while the rest got nothing.

  test "the spotlight is drawn from the members who have posted recently" do
    active = create_user(username: "active_member")
    3.times { active.tweets.create!(body: "busy") }
    quiet = create_user(username: "quiet_spot")
    quiet.tweets.create!(body: "one post")

    seen = 200.times.map { BotEngine.find_spotlight&.username }.tally

    assert_includes seen.keys, "active_member"
    assert_includes seen.keys, "quiet_spot",
                    "a less active member should still get a turn"
    assert_operator seen["active_member"], :>, seen["quiet_spot"],
                    "the more active member should come up more often"
  end

  test "a member who has not posted recently is not the spotlight" do
    stale = create_user(username: "stale_member")
    post = stale.tweets.create!(body: "old news")
    post.update_columns(created_at: (BotEngine::SPOTLIGHT_WINDOW + 1.hour).ago)

    refute_equal "stale_member", BotEngine.find_spotlight&.username
  end

  test "no member posting recently means no spotlight" do
    create_user(username: "silent_member")

    assert_nil BotEngine.find_spotlight
  end

  test "the configured account is the spotlight whenever it has posted" do
    named = create_user(username: BotEngine::SPOTLIGHT_DEFAULT)
    named.tweets.create!(body: "the account everybody watches")
    create_user(username: "someone_else").tweets.create!(body: "also posting")

    assert_equal BotEngine::SPOTLIGHT_DEFAULT, BotEngine.find_spotlight&.username
  end

  # The deviation is what stops the spotlight from swallowing the whole
  # population: part of it carries on regardless, which is how the other
  # members keep getting attention.

  test "some of the population follows the spotlight and some does not" do
    assert_operator BotEngine::SPOTLIGHT_DEVIATION, :>, 0.0,
                    "a zero deviation would focus every bot on one account"
    assert_operator BotEngine::SPOTLIGHT_DEVIATION, :<, 1.0,
                    "a deviation of one would ignore the spotlight entirely"
  end

  # Who a bot follows or messages.

  test "members are weighted above other simulated accounts" do
    assert_operator BotEngine::HUMAN_WEIGHT, :>, BotEngine::BOT_WEIGHT,
                    "members should be the preferred target"
  end

  test "members stay in the pool even once a bot follows them" do
    member = create_user(username: "followed_member")
    Follow.create!(follower: @bots.first, followee: member)

    seen = 40.times.map { BotEngine.send(:pick_user, @bots.first, Random.new) }.compact

    assert_includes seen.map(&:id), member.id,
                    "a followed member should still be reachable for a message"
  end

  test "a member can be picked for a follow" do
    member = create_user(username: "picked_member")
    seen = 40.times.map { BotEngine.send(:pick_user, @bots.first, Random.new) }.compact

    assert_includes seen.map(&:id), member.id
  end

  test "a follow aimed at someone already followed changes nothing" do
    member = create_user(username: "already_follow")
    bot = @bots.first
    Follow.create!(follower: bot, followee: member)
    # Nobody else is available, so the pick can only land on the member the bot
    # already follows.
    User.where.not(id: [ bot.id, member.id ]).update_all(is_suspended: true)

    assert_no_difference "Follow.count" do
      BotEngine.send(:do_follow, bot, bot.persona_hash, Random.new(1))
    end

    assert_equal 1, Follow.where(follower_id: bot.id, followee_id: member.id).count
  end

  test "a follow of a member notifies them" do
    member = create_user(username: "newly_followed")
    bot = @bots.first
    # The member is the only account the bot can pick.
    User.where.not(id: [ bot.id, member.id ]).update_all(is_suspended: true)

    assert_difference "Notification.count", 1 do
      BotEngine.send(:do_follow, bot, bot.persona_hash, Random.new(1))
    end

    assert Notification.exists?(user: member, actor: bot, kind: "follow")
  end

  test "a walked account is a valid follow target even when it has no posts" do
    quiet = create_user(username: "quiet_target")
    bot = @bots.first

    # A member with nothing on their timeline is still somebody a bot can
    # follow; the pool is drawn from accounts, not from posts.
    User.where.not(id: [ bot.id, quiet.id ]).update_all(is_suspended: true)

    assert_difference "Follow.count", 1 do
      BotEngine.send(:do_follow, bot, bot.persona_hash, Random.new(1))
    end
  end

  test "bots go on to follow members in the ordinary course of things" do
    member = create_user(username: "wanted_member")

    # A real runner revisits the population every couple of seconds for days, so
    # a bot acts many times over. Ticking alone does not reproduce that: every
    # action books the account at least 20 seconds out, so a second tick finds
    # nobody due and performs nothing. Re-arming the population between ticks is
    # what turns this into the long run the test is about - 400 ticks x 20 bots.
    400.times do
      @bots.each { |bot| bot.update_columns(next_action_at: Time.current) }
      BotEngine.tick
    end

    assert Follow.exists?(followee_id: member.id),
           "a member should be followed by somebody over a long run"
  end
end