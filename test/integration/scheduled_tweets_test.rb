require "test_helper"

# Scheduling was the last control in 2019's composer. The whole feature rests on
# one idea: a post with a future `scheduled_at` is withheld from every reader
# until that moment passes, and then appears on its own. These cover the
# withholding, the guards on a bad schedule, and the writer's own queue.
class ScheduledTweetsTest < ActionDispatch::IntegrationTest
  setup do
    @me = create_user(username: "sched_me")
    @other = create_user(username: "sched_other")
    sign_in @me
  end

  # --- posting a scheduled tweet ------------------------------------------

  test "a future schedule is stored and the post is withheld from the timeline" do
    assert_difference "Tweet.count", 1 do
      post compose_path, params: { body: "later", scheduled_at: 2.hours.from_now.strftime("%Y-%m-%d %H:%M") }
    end

    tweet = Tweet.order(:id).last
    assert_not_nil tweet.scheduled_at
    assert tweet.scheduled_pending?

    # Absent from the home feed and from the author's own profile stream.
    get home_path
    assert_response :success
    assert_not_includes response.body, "later"

    get profile_path(@me.username)
    assert_not_includes response.body, "later"
  end

  test "a scheduled tweet appears once its moment has passed" do
    tweet = Tweet.create!(user: @me, body: "due now", scheduled_at: 1.minute.from_now)

    get home_path
    assert_not_includes response.body, "due now"

    travel 2.minutes do
      get home_path
      assert_includes response.body, "due now"
      assert_not tweet.reload.scheduled_pending?
    end
  end

  test "a schedule in the past is refused and writes nothing" do
    assert_no_difference "Tweet.count" do
      post compose_path, params: { body: "too late", scheduled_at: 1.hour.ago.strftime("%Y-%m-%d %H:%M") }
    end

    assert_response :redirect
    follow_redirect!
    assert_match(/future/i, response.body)
  end

  test "an unreadable schedule is refused rather than silently published" do
    assert_no_difference "Tweet.count" do
      post compose_path, params: { body: "garbled", scheduled_at: "next tuesday-ish" }
    end

    assert_response :redirect
    follow_redirect!
    assert_match(/could not be read/i, response.body)
  end

  test "a scheduled reply notifies nobody" do
    parent = Tweet.create!(user: @other, body: "the original")

    assert_no_difference "Notification.count" do
      post compose_path, params: {
        body: "a scheduled reply",
        parent_id: parent.id,
        scheduled_at: 3.hours.from_now.strftime("%Y-%m-%d %H:%M")
      }
    end

    assert Tweet.order(:id).last.scheduled_pending?
  end

  test "an unscheduled post still notifies as before" do
    parent = Tweet.create!(user: @other, body: "the original")

    assert_difference "Notification.count", 1 do
      post compose_path, params: { body: "an ordinary reply", parent_id: parent.id }
    end
  end

  # --- the writer's own queue ---------------------------------------------

  test "the scheduled tab lists only your own pending posts" do
    mine = Tweet.create!(user: @me, body: "my queue", scheduled_at: 4.hours.from_now)
    Tweet.create!(user: @me, body: "already out", scheduled_at: 1.hour.ago)
    Tweet.create!(user: @other, body: "someone else's queue", scheduled_at: 4.hours.from_now)

    get profile_path(@me.username, tab: "scheduled")
    assert_response :success
    assert_includes response.body, "my queue"
    assert_not_includes response.body, "already out"
    assert_not_includes response.body, "someone else's queue"

    # Only the writer sees the tab and the list at all.
    delete logout_path
    sign_in @other
    get profile_path(@me.username, tab: "scheduled")
    assert_response :success
    assert_not_includes response.body, "my queue"
  end

  test "the scheduled tab says outright that the posts are not visible yet" do
    Tweet.create!(user: @me, body: "pending post", scheduled_at: 5.hours.from_now)

    get profile_path(@me.username, tab: "scheduled")
    assert_includes response.body, "not visible to anyone yet"
  end

  test "the composer offers a schedule control" do
    get home_path
    assert_response :success
    assert_includes response.body, "data-schedule-open"
    assert_includes response.body, "data-schedule-panel"
  end

  # --- the count stays honest ---------------------------------------------

  test "the tweet count does not include a post that is not out yet" do
    Tweet.create!(user: @me, body: "published", scheduled_at: 1.hour.ago)
    Tweet.create!(user: @me, body: "pending", scheduled_at: 1.hour.from_now)

    assert_equal 1, @me.reload.tweet_count
  end
end
