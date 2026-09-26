require "test_helper"

# 2019 emptied every stream surface into the same centred shape: a glyph over a
# heading and a line naming what would fill it. The audit has called out the
# bare sentence-in-a-list-row pattern repeatedly, because it reads as a row that
# failed to render rather than as a deliberate empty screen. These are fidelity
# guards: the three surfaces below were the last streams still using it.
class StreamEmptyStatesTest < ActionDispatch::IntegrationTest
  setup do
    @alice = create_user(username: "alice")
    @bob = create_user(username: "bob")
  end

  # -------------------------------------------------------- home timeline

  test "an empty home timeline shows the 2019 empty state, not a bare row" do
    sign_in @alice

    get home_path
    assert_response :success
    assert_match "Your Home timeline is empty", response.body
    assert_match "post the first Tweet", response.body
    assert_select ".timeline .empty-state .empty-state-icon"
    assert_select ".timeline .empty", count: 0
  end

  # The state is the absence of posts, so the account's own post replaces it.
  test "the home empty state disappears once the account posts" do
    sign_in @alice

    get home_path
    assert_select ".timeline .empty-state", count: 1

    Tweet.create!(user: @alice, body: "the first post from alice")

    get home_path
    assert_select ".timeline .empty-state", count: 0
    assert_match "the first post from alice", response.body
  end

  # ----------------------------------------------------- permalink replies

  test "a post with no replies shows the 2019 empty state, not a bare row" do
    post = Tweet.create!(user: @bob, body: "nobody has answered this yet")
    sign_in @alice

    get tweet_path(post)
    assert_response :success
    assert_match "No replies yet", response.body
    assert_match "Be the first to reply", response.body
    assert_select ".permalink-replies .empty-state .empty-state-icon"
    assert_select ".permalink-replies .empty", count: 0
  end

  test "the reply empty state disappears once a reply exists" do
    post = Tweet.create!(user: @bob, body: "nobody has answered this yet")
    sign_in @alice

    get tweet_path(post)
    assert_select ".permalink-replies .empty-state", count: 1

    Tweet.create!(user: @alice, body: "here is an answer", parent: post)

    get tweet_path(post)
    assert_select ".permalink-replies .empty-state", count: 0
    assert_match "here is an answer", response.body
  end

  # ------------------------------------------------------- explore landing

  # A landing section falls back to the site-wide stream when nothing matches
  # its terms, so the state only surfaces when the site itself has no posts.
  test "an explore landing section with no posts shows the 2019 empty state" do
    sign_in @alice

    get explore_path(tab: "sports")
    assert_response :success
    assert_match "Nothing to see here yet", response.body
    assert_select ".timeline .empty-state .empty-state-icon"
    assert_select ".timeline .empty-note", count: 0
  end

  test "an explore landing section with posts renders them instead of the state" do
    Tweet.create!(user: @bob, body: "the game was a great match")
    sign_in @alice

    get explore_path(tab: "sports")
    assert_response :success
    assert_select ".timeline .empty-state", count: 0
    assert_match "the game was a great match", response.body
  end

  # The search no-results state keeps its query-specific wording; the shared
  # partial must not have flattened it into the generic landing copy.
  test "a search that matches nothing keeps its query-specific empty state" do
    sign_in @alice

    get explore_path(q: "zzzznothing")
    assert_response :success
    assert_match "No results for", response.body
    assert_match "zzzznothing", response.body
    assert_select ".timeline .empty-state .empty-state-icon"
  end
end
