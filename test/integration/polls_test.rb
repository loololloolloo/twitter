require "test_helper"

# Polls were one of the four composer controls in 2019's redesigned composer
# (photo, GIF, poll, emoji). These cover the builder's rules, the vote path and
# the result split, since a poll that reports the wrong share or lets an account
# vote twice is worse than one that does not exist.
class PollsTest < ActionDispatch::IntegrationTest
  setup do
    @me = create_user(username: "poll_me")
    @other = create_user(username: "poll_other")
    sign_in @me
  end

  def make_poll(body: "Pick one", options: %w[Cats Dogs], duration: "1d", author: @me)
    tweet = Tweet.create!(user: author, body: body)
    poll = Poll.build_for(tweet, options: options, duration: duration)
    poll.tweet = tweet
    poll.save!
    poll
  end

  # --- the builder ---------------------------------------------------------

  test "a poll takes two to four choices and drops the rest" do
    poll = make_poll(options: %w[A B C D E])

    assert_equal [ "A", "B", "C", "D" ], poll.poll_options.map(&:label)
    assert_equal Poll::MAX_OPTIONS, poll.poll_options.size
  end

  test "a poll with fewer than two real choices is not built" do
    tweet = Tweet.create!(user: @me, body: "half a poll")

    assert_nil Poll.build_for(tweet, options: [ "only" ], duration: "1d")
    assert_nil Poll.build_for(tweet, options: [ "  ", "" ], duration: "1d")
    assert_nil Poll.build_for(tweet, options: [], duration: "1d")
    # Blanks between real choices are dropped rather than shifting them.
    assert_equal [ "a", "b" ], Poll.build_for(tweet, options: [ "a", "", "b" ], duration: "1d").poll_options.map(&:label)
  end

  test "a poll duration falls back to one day and clamps a bad value" do
    poll = make_poll(duration: "1h")
    assert_in_delta 1.hour.from_now, poll.closes_at, 60

    fallback = make_poll(body: "bad duration", duration: "forever")
    assert_in_delta 1.day.from_now, fallback.closes_at, 60
  end

  test "the choices keep the order the writer entered them" do
    poll = make_poll(options: %w[Zebra Apple Mango])

    assert_equal %w[Zebra Apple Mango], poll.poll_options.map(&:label)
    assert_equal [ 0, 1, 2 ], poll.poll_options.map(&:position)
  end

  # --- posting a poll ------------------------------------------------------

  test "the composer offers poll and emoji alongside image and GIF" do
    get home_path
    assert_response :success

    assert_match "data-poll-open", response.body, "the composer should offer a poll control"
    assert_match "data-poll-panel", response.body, "the composer should carry a poll builder"
    assert_match "data-emoji-open", response.body, "the composer should offer an emoji control"
    assert_match "data-emoji-panel", response.body, "the composer should carry an emoji picker"
    assert_match(%r{name="poll\[options\]\[\]"}, response.body, "the poll choices should submit as a list")
    assert_match(%r{name="poll\[duration\]"}, response.body, "the poll should submit its length")
  end

  test "posting a poll attaches it to the new tweet" do
    post compose_path, params: { body: "Pick one", poll: { options: %w[Cats Dogs], duration: "1d" } }
    assert_response :redirect

    tweet = Tweet.visible.find_by(user: @me, body: "Pick one")
    assert_not_nil tweet.poll, "the posted tweet should carry its poll"
    assert_equal %w[Cats Dogs], tweet.poll.poll_options.map(&:label)
  end

  test "a poll-only post is accepted without a body" do
    post compose_path, params: { body: "", poll: { options: %w[Yes No], duration: "1d" } }
    assert_response :redirect

    assert Tweet.visible.where(user: @me).any? { |t| t.poll.present? },
           "a poll with no body should still post"
  end

  test "a post with neither body nor poll nor media is still refused" do
    assert_no_difference -> { Tweet.visible.count } do
      post compose_path, params: { body: "", poll: { options: [ "", "" ], duration: "1d" } }
    end
    assert_response :redirect
  end

  # --- voting --------------------------------------------------------------

  test "a reader votes once and cannot vote again" do
    poll = make_poll
    option = poll.poll_options.first

    assert_difference -> { PollVote.count }, 1 do
      post poll_option_vote_path(option)
    end
    assert_response :redirect
    assert poll.reload.voted_by?(@me)

    assert_no_difference -> { PollVote.count } do
      post poll_option_vote_path(poll.poll_options.last)
    end
    assert_equal option.id, poll.reload.poll_votes.find_by(user: @me).poll_option_id,
                 "the first vote should stand"
  end

  test "votes from different accounts are counted separately" do
    poll = make_poll
    first, second = poll.poll_options.to_a

    post poll_option_vote_path(first)
    sign_in @other
    post poll_option_vote_path(second)

    assert_equal 2, poll.reload.total_votes
  end

  test "the result split always sums to 100" do
    poll = make_poll(options: %w[A B C])

    # Three votes over three choices: the rounding remainder has to land
    # somewhere, or the bars read as 99%.
    poll.poll_options.each_with_index do |option, index|
      voter = create_user(username: "poll_voter_#{index}")
      poll.poll_votes.create!(user: voter, poll_option: option)
    end

    assert_equal 100, poll.shares.values.sum
    assert_equal [ 33, 33, 34 ], poll.poll_options.map { |o| poll.shares[o.id] }.sort
  end

  test "a closed poll reveals its result and refuses a vote" do
    poll = make_poll
    poll.update!(closes_at: 1.minute.ago)
    assert poll.closed?

    assert_no_difference -> { PollVote.count } do
      post poll_option_vote_path(poll.poll_options.first)
    end
    assert_response :redirect
  end

  test "an open poll hides its result until the reader has voted" do
    poll = make_poll
    poll.poll_votes.create!(user: @other, poll_option: poll.poll_options.first)

    get tweet_path(poll.tweet)
    assert_response :success
    assert_match "poll-choice-btn", response.body, "an open poll the reader has not voted in should offer buttons"
    assert_no_match(/poll-result/, response.body, "an open poll must not reveal the split")

    post poll_option_vote_path(poll.poll_options.last)

    get tweet_path(poll.tweet)
    assert_response :success
    assert_match "poll-result", response.body, "after voting the split should be shown"
  end

  test "a poll is rendered on the permalink and in the stream" do
    poll = make_poll(body: "Which one #pollcheck")

    get tweet_path(poll.tweet)
    assert_response :success
    assert_match "poll-options", response.body
    assert_match "Cats", response.body

    get home_path
    assert_response :success
    assert_match "poll-options", response.body
  end

  # --- safety --------------------------------------------------------------

  test "an option cannot be voted in through another poll's post" do
    # The option belongs to a post the reader cannot see, so guessing its id
    # must not let them vote.
    hidden = make_poll(body: "hidden poll", author: @other)
    hidden.tweet.update!(is_deleted: true)

    assert_no_difference -> { PollVote.count } do
      post poll_option_vote_path(hidden.poll_options.first)
    end
    assert_response :not_found
  end

  test "deleting a post takes its poll, choices and votes with it" do
    poll = make_poll
    poll.poll_votes.create!(user: @other, poll_option: poll.poll_options.first)
    tweet_id = poll.tweet_id
    poll_id = poll.id

    Tweet.find(tweet_id).destroy

    assert_nil Poll.find_by(id: poll_id)
    assert_equal 0, PollOption.where(poll_id: poll_id).count
    assert_equal 0, PollVote.where(poll_id: poll_id).count
  end

  test "a vote must name an option from its own poll" do
    poll = make_poll
    other_poll = make_poll(body: "another poll")

    vote = PollVote.new(poll: poll, poll_option: other_poll.poll_options.first, user: @other)

    assert_not vote.valid?
    assert_includes vote.errors.full_messages.join, "does not belong to that poll"
  end
end