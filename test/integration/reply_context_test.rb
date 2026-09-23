require "test_helper"

# The 2019 client labelled every reply in a stream with "Replying to @handle"
# above the body, linking to the account being answered. Without it a reply
# reads as a detached post - the reader cannot tell it is half of a
# conversation - so this is fidelity, not decoration.
#
# The line is also a disclosure, which is why the guards matter as much as the
# happy path: naming the parent's author tells the viewer who wrote a post they
# may not be allowed to open.
class ReplyContextTest < ActionDispatch::IntegrationTest
  setup do
    @alice = create_user(username: "alice")
    @bob = create_user(username: "bob")
    @carol = create_user(username: "carol")

    @parent = Tweet.create!(user: @bob, body: "original question from bob")
    @reply = Tweet.create!(user: @carol, body: "an answer from carol", parent: @parent)
  end

  # --------------------------------------------------------------- the line

  test "a reply in the home timeline names the account it answers" do
    sign_in @alice

    get home_path
    assert_response :success
    assert_select ".tweet-reply-context" do
      assert_match "Replying to", response.body
      assert_select "a[href=?]", profile_path("bob"), text: "@bob"
    end
  end

  test "the reply label links to the parent author's profile" do
    sign_in @alice

    get home_path
    assert_response :success
    assert_select ".tweet-reply-context a[href=?]", profile_path("bob")
  end

  test "an original post carries no reply label" do
    sign_in @alice

    get home_path
    assert_response :success
    # Bob's original is in the stream too; only Carol's reply is labelled, so
    # exactly one label renders for the two posts.
    assert_select ".tweet-reply-context", 1
  end

  test "a reply on the permalink names the account it answers" do
    sign_in @alice

    get tweet_path(@reply)
    assert_response :success
    assert_select ".tweet-reply-context" do
      assert_match "Replying to", response.body
      assert_select "a[href=?]", profile_path("bob"), text: "@bob"
    end
  end

  test "a reply opened on its own permalink names the account it answers" do
    sign_in @alice

    get tweet_path(@reply)
    assert_response :success
    assert_select ".tweet-reply-context", 1
  end

  test "the profile Tweets and replies tab labels the replies it shows" do
    sign_in @alice

    get profile_path("carol", tab: "replies")
    assert_response :success
    assert_select ".tweet-reply-context" do
      assert_select "a[href=?]", profile_path("bob"), text: "@bob"
    end
  end

  test "the default profile tab hides replies and so carries no label" do
    sign_in @alice

    get profile_path("carol")
    assert_response :success
    assert_select ".tweet-reply-context", 0
  end

  # -------------------------------------------------------------- the guards

  # A retweet of a reply is not itself a reply: the retweeter answered nobody,
  # so the retweeted entry must not borrow the original's label. Carol's reply
  # is in the same feed as an original post and is still labelled; only the
  # retweeted copy is not.
  test "a retweet of a reply does not claim the retweeter is replying" do
    sign_in @alice
    Tweet.create!(user: @alice, body: "", retweet_of: @reply)

    get home_path
    assert_response :success

    retweeted_row = nil
    assert_select "li.tweet" do |rows|
      retweeted_row = rows.find { |row| row.css(".rt-flag").any? }
    end
    assert_not_nil retweeted_row, "the retweeted entry was not in the feed"
    assert_empty retweeted_row.css(".tweet-reply-context")
    assert_match "an answer from carol", retweeted_row.text
  end

  # The label names the parent's author, so it must obey the same visibility
  # rule as the parent itself. A protected account's handle is not disclosed to
  # a viewer who cannot read the protected post.
  test "a reply to a protected account is unlabelled for an outsider" do
    @bob.update!(protected: true)
    sign_in @alice

    get tweet_path(@reply)
    assert_response :success
    assert_select ".tweet-reply-context", 0
    assert_no_match "@bob", response.body
  end

  # The same rule governs the conversation block above the focused post: a
  # protected parent the viewer may not open must not be rendered there just
  # because the reply below it is readable.
  test "the permalink withholds a protected parent from an outsider" do
    @bob.update!(protected: true)
    sign_in @alice

    get tweet_path(@reply)
    assert_response :success
    assert_select ".permalink-ancestors", 0
    assert_no_match "original question from bob", response.body
  end

  test "the permalink shows the protected parent to an approved follower" do
    @bob.update!(protected: true)
    Follow.create!(follower: @alice, followee: @bob)
    sign_in @alice

    get tweet_path(@reply)
    assert_response :success
    assert_select ".permalink-ancestors"
    assert_match "original question from bob", response.body
  end

  test "a reply to a protected account is labelled for an approved follower" do
    @bob.update!(protected: true)
    Follow.create!(follower: @alice, followee: @bob)
    sign_in @alice

    get tweet_path(@reply)
    assert_response :success
    assert_select ".tweet-reply-context a[href=?]", profile_path("bob")
  end

  test "a reply to a protected account is labelled for its author" do
    @bob.update!(protected: true)
    Follow.create!(follower: @carol, followee: @bob)
    sign_in @carol

    get tweet_path(@reply)
    assert_response :success
    assert_select ".tweet-reply-context a[href=?]", profile_path("bob")
  end

  # A permanently banned profile is a notice, not a profile, so its handle must
  # not be surfaced as conversation context anywhere.
  test "a reply to a permanently banned account carries no label" do
    @bob.update!(is_banned: true, ban_permanent: true)
    sign_in @alice

    get tweet_path(@reply)
    assert_response :success
    assert_select ".tweet-reply-context", 0
  end

  test "a deleted parent leaves the reply unlabelled" do
    @parent.update!(is_deleted: true)
    sign_in @alice

    get tweet_path(@reply)
    assert_response :success
    assert_select ".tweet-reply-context", 0
  end

  test "a thread reply names the post it answers, not the thread root" do
    grandparent = Tweet.create!(user: @alice, body: "the thread root")
    middle = Tweet.create!(user: @bob, body: "the middle", parent: grandparent)
    leaf = Tweet.create!(user: @carol, body: "the leaf", parent: middle)
    sign_in @alice

    get tweet_path(leaf)
    assert_response :success
    assert_select ".tweet-reply-context a[href=?]", profile_path("bob")
  end
end
