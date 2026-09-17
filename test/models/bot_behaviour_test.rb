require "test_helper"

# The simulation is meant to move the way a browsing population moves, not the
# way a scheduler fires. These tests pin the properties that make that true:
# reading outweighs writing, impressions are recorded, and threads continue.
class BotBehaviourTest < ActiveSupport::TestCase
  setup do
    @human = create_user(username: "member", role: "owner")
    @bot = create_user(
      username: "reader",
      is_bot: true,
      persona: PersonaGenerator.build(4242).to_json
    )
    @other = create_user(username: "poster", is_bot: true,
                         persona: PersonaGenerator.build(99).to_json)

    # Something for the bot to look at.
    5.times { |i| @human.tweets.create!(body: "post number #{i} about coffee") }
  end

  test "reading outweighs writing across a long run of choices" do
    rng = Random.new(7)
    counts = Hash.new(0)
    2_000.times { counts[BotEngine.send(:choose_action, @bot.persona_hash, rng)] += 1 }

    passive = counts[:view] + counts[:browse] + counts[:scroll]
    active = counts.values.sum - passive

    assert passive > active,
           "expected reading to dominate, got #{passive} passive vs #{active} active"
    assert counts[:view].positive?
    assert counts[:scroll].positive?
    assert counts[:browse].positive?
  end

  test "viewing a tweet records an impression with a plausible dwell time" do
    tweet = @human.tweets.first

    assert_difference "TweetView.count", 1 do
      BotEngine.send(:do_view, @bot, @bot.persona_hash, Random.new(1))
    end

    view = TweetView.last
    assert_equal @bot.id, view.user_id
    assert_includes @human.tweets.pluck(:id), view.tweet_id
    assert view.dwell_seconds.between?(1, 300), "dwell #{view.dwell_seconds} out of range"
  end

  test "viewing a post removes it from later fresh picks" do
    BotEngine.send(:do_view, @bot, @bot.persona_hash, Random.new(3))
    seen = @bot.tweet_views.pluck(:tweet_id).to_set

    refute_empty seen

    # A fresh pick must never hand back something already read.
    20.times do |i|
      picked = BotEngine.send(:pick_tweet, @bot, Random.new(i), fresh: true)
      next if picked.nil?

      refute_includes seen, picked.id, "fresh pick returned an already-viewed tweet"
    end

    # Once every candidate has been read there is nothing fresh left.
    Tweet.visible.where.not(user_id: @bot.id).pluck(:id).each do |id|
      TweetView.record!(user: @bot, tweet: Tweet.find(id), dwell_seconds: 5)
    end
    assert_nil BotEngine.send(:pick_tweet, @bot, Random.new(3), fresh: true)
  end

  test "scrolling records impressions from accounts the bot follows" do
    Follow.create!(follower: @bot, followee: @human)

    BotEngine.send(:do_scroll, @bot, @bot.persona_hash, Random.new(5))

    # A scroll reads one to three posts, never more.
    assert_includes 1..3, TweetView.where(user_id: @bot.id).count
    @bot.tweet_views.each do |view|
      assert_equal @human.id, view.tweet.user_id
    end
  end

  test "browsing a profile records a profile view" do
    assert_difference "ProfileView.count", 1 do
      BotEngine.send(:do_browse, @bot, @bot.persona_hash, Random.new(11))
    end

    view = ProfileView.last
    assert_equal @bot.id, view.viewer_id
    refute_equal @bot.id, view.user_id
  end

  test "a direct message continues an open thread instead of starting one" do
    conversation = DmConversation.between(@bot, @other)
    opener = conversation.dm_messages.create!(sender: @other, body: "hey, is the coffee place any good")

    # 65% of the time the bot answers the open thread; the rest of the time it
    # starts a fresh one with someone else. Over many draws the opening reply
    # must land in the existing thread and react to what was said.
    replies = []
    30.times do |i|
      BotEngine.send(:do_dm, @bot, @bot.persona_hash, Random.new(i))
      last = conversation.reload.dm_messages.chronological.last
      replies << last if last.sender_id == @bot.id && last.id > opener.id
    end

    refute_empty replies, "the bot never continued the open thread"
    assert_match(/coffee|good|place|weekend|list|tip|goes|problem|right|asked/,
                 replies.first.body)
  end

  test "a bot never sends two messages in a row in the same thread" do
    conversation = DmConversation.between(@bot, @other)
    conversation.dm_messages.create!(sender: @other, body: "morning")

    # Answer once, then let the bot act again. Because it spoke last, it must
    # not answer itself; any new message belongs to a different conversation.
    10.times do |i|
      BotEngine.send(:do_dm, @bot, @bot.persona_hash, Random.new(100 + i))
    end

    bodies = conversation.dm_messages.chronological.pluck(:sender_id)
    bodies.each_cons(2) do |left, right|
      refute left == right && left == @bot.id,
             "bot sent two consecutive messages in one thread"
    end
  end

  test "a direct message reply quotes the message it answers" do
    body = ContentGenerator.dm_reply(@bot.persona_hash, "the coffee place on main street is great")
    assert_match(/coffee|street|place|great|main/, body)
  end

  test "every persona carries a dwell factor" do
    10.times do |seed|
      persona = PersonaGenerator.build(seed)
      assert persona.key?("dwell_factor"), "seed #{seed} has no dwell_factor"
      assert persona["dwell_factor"].to_f >= 0
    end
  end

  test "ticking a bot books its next action in the future" do
    # Give both bots explicit timestamps: a NULL next_action_at sorts first in
    # the engine's ordering, so the target has to be set deliberately.
    @bot.update_columns(next_action_at: 1.minute.ago, actions_performed: 0)
    @other.update_columns(next_action_at: 1.hour.from_now)

    assert_equal 1, BotEngine.tick(count: 1)

    @bot.reload
    assert @bot.next_action_at > Time.current
    assert_equal 1, @bot.actions_performed
  end
end