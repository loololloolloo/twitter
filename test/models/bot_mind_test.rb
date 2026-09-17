require "test_helper"

# A belief is the position an account holds on a subject, kept alongside the
# reason for it. Reading about a subject it already has a view on moves that
# view, and a view that crosses zero is a change of mind: the old reason no
# longer fits and has to be replaced.
class BotMindTest < ActiveSupport::TestCase
  setup do
    @user = create_user(username: "mind_bot", is_bot: true,
                        persona: PersonaGenerator.build(7).to_json)
    @mind = BotMind.load(@user)
  end

  # The regression: the guard on a change of mind called `sign` on a Float,
  # which Ruby does not define, so liking any post about a subject the account
  # held a belief on raised NoMethodError and took the whole tick down.
  test "nudging a belief does not raise" do
    topic = "coffee"
    @mind.nudge_opinion!(topic, 0.1)

    assert @mind.opinion_on(topic).is_a?(Numeric)
  end

  test "a nudge is applied to the stored position" do
    topic = "tea"
    @mind.nudge_opinion!(topic, 0.2)
    first = @mind.opinion_on(topic)
    @mind.nudge_opinion!(topic, 0.2)

    assert_operator @mind.opinion_on(topic), :>, first
  end

  test "a position is clamped to the scale it is measured on" do
    topic = "rain"

    20.times { @mind.nudge_opinion!(topic, 0.3) }

    assert_operator @mind.opinion_on(topic), :<=, 1.0
    assert_operator @mind.opinion_on(topic), :>=, -1.0
  end

  # Crossing zero keeps the position but replaces the reason, which is the
  # behaviour the broken guard was there to protect. The starting position is
  # random, so it is set here rather than left to chance.
  test "crossing zero replaces the reason behind the belief" do
    topic = "winter"
    record = @mind.belief_on(topic)
    record["position"] = -0.3
    before = record["basis"]

    @mind.nudge_opinion!(topic, 0.5)
    after = @mind.belief_on(topic)

    assert_operator after["position"], :>, 0, "the position should have crossed zero"
    assert after["basis"].present?, "a change of mind needs a reason"
    assert_not_nil after["formed_at"]
    assert_not_equal before, after["basis"] if before.present?
  end

  test "staying on the same side of zero keeps the reason" do
    topic = "summer"
    record = @mind.belief_on(topic)
    record["position"] = 0.3
    before = record["basis"]

    @mind.nudge_opinion!(topic, 0.1)

    assert_equal before, @mind.belief_on(topic)["basis"]
  end

  test "absorbing a post does not raise once a belief exists" do
    topic = BotMind.extract_topic("music is the best thing ever")
    assert topic.present?, "the fixture text needs a recognised subject"

    @mind.nudge_opinion!(topic, -0.05)
    @mind.save

    # The path that originally crashed: a post about a subject the account
    # already holds a belief on.
    assert_nothing_raised do
      BotMind.load(@user).absorb!("music is the best thing ever", from_id: nil, weight: 0.1)
    end
  end
end