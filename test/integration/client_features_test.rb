require "test_helper"

# The social and platform features added on top of the 2019 redesign: saved
# posts, lists, follow requests, reports, blocks and mutes, protected accounts,
# quote tweets, hidden replies and per-post activity.
#
# These are integration tests on purpose. Each feature spans a controller, a
# model rule and a view, and the interesting failures are the ones where the
# three disagree - a scope that lets a page through, a form that posts to the
# wrong endpoint - which a unit test of any one piece would not catch.
class ClientFeaturesTest < ActionDispatch::IntegrationTest
  setup do
    @alice = create_user(username: "alice")
    @bob = create_user(username: "bob")
    @carol = create_user(username: "carol")

    @post = Tweet.create!(user: @bob, body: "hello from bob")
  end

  # ------------------------------------------------------------ bookmarks

  test "a signed-in account can save and unsave a post" do
    sign_in @alice

    post bookmark_tweet_path(@post)
    assert_response :redirect
    assert Bookmark.exists?(user: @alice, tweet: @post)

    get bookmarks_path
    assert_response :success
    assert_match "hello from bob", response.body

    delete bookmark_tweet_path(@post)
    assert_response :redirect
    assert_not Bookmark.exists?(user: @alice, tweet: @post)
  end

  # 2019's Bookmarks screen, with nothing saved, was a centred bookmark glyph
  # over "You haven't added any Tweets to your Bookmarks yet" and a sub-line
  # pointing at the share icon - not a bare sentence in a list row.
  test "an empty bookmarks screen shows the 2019 empty state" do
    sign_in @alice

    get bookmarks_path
    assert_response :success
    assert_match "You haven", response.body
    assert_match "Tweets to your Bookmarks yet", response.body
    assert_match "share icon", response.body
    assert_match "empty-state", response.body
    assert_select ".empty-state .empty-state-icon"
  end

  # The empty state is the absence of saved posts, so saving one replaces it.
  test "the bookmarks empty state disappears once a post is saved" do
    sign_in @alice

    get bookmarks_path
    assert_match "empty-state", response.body

    post bookmark_tweet_path(@post)
    get bookmarks_path
    assert_no_match(/empty-state/, response.body)
  end

  test "saved posts are private to the account that saved them" do
    sign_in @alice
    post bookmark_tweet_path(@post)

    sign_in @carol
    get bookmarks_path
    assert_response :success
    assert_no_match "hello from bob", response.body
  end

  test "the bookmark toggle answers with the new state as json" do
    sign_in @alice

    post bookmark_tweet_path(@post), as: :json
    assert_response :success
    assert_equal true, JSON.parse(response.body)["bookmarked"]

    delete bookmark_tweet_path(@post), as: :json
    assert_response :success
    assert_equal false, JSON.parse(response.body)["bookmarked"]
  end

  test "clearing saved posts removes only the signed-in account's own" do
    Bookmark.create!(user: @alice, tweet: @post)
    Bookmark.create!(user: @carol, tweet: @post)

    sign_in @alice
    delete clear_bookmarks_path
    assert_response :redirect

    assert_not Bookmark.exists?(user: @alice, tweet: @post)
    assert Bookmark.exists?(user: @carol, tweet: @post)
  end

  test "signed-out visitors cannot reach saved posts" do
    get bookmarks_path
    assert_response :redirect
  end

  # ---------------------------------------------------------------- lists

  test "a list can be created and read" do
    sign_in @alice

    assert_difference -> { List.count }, 1 do
      post lists_path, params: { list: { name: "Tech", description: "People" } }
    end

    list = List.last
    assert_equal @alice.id, list.user_id

    get list_path(list)
    assert_response :success
  end

  test "a list timeline shows its members' posts without following them" do
    list = List.create!(user: @alice, name: "Reading")
    list.list_memberships.create!(user: @bob)

    sign_in @alice
    get list_path(list)
    assert_response :success
    assert_match "hello from bob", response.body

    assert_not Follow.exists?(follower_id: @alice.id, followee_id: @bob.id),
               "a list must not create a follow"
  end

  # 2019's list header printed the member count and the follower count inline
  # beside the name. Membership and following are separate facts - you can read
  # a list without being on it - so both have to render.
  test "a list header shows the member and follower counts" do
    list = List.create!(user: @alice, name: "Reading")
    list.list_memberships.create!(user: @bob)
    list.list_memberships.create!(user: @carol)
    list.list_subscriptions.create!(user: @alice)

    sign_in @alice
    get list_path(list)
    assert_response :success
    assert_match "2 members", response.body
    assert_match "1 follower", response.body
  end

  test "an account can follow and unfollow another account's list without joining it" do
    list = List.create!(user: @bob, name: "Public")

    sign_in @alice
    assert_difference -> { ListSubscription.count }, 1 do
      post list_follow_path(list)
    end
    assert_response :redirect
    assert list.subscribed_by?(@alice)
    assert_not list.includes?(@alice), "following a list must not add the account to it"
    assert_not Follow.exists?(follower_id: @alice.id, followee_id: @bob.id)

    get list_path(list)
    assert_match "1 follower", response.body

    assert_difference -> { ListSubscription.count }, -1 do
      delete list_follow_path(list)
    end
    assert_not list.subscribed_by?(@alice)
  end

  test "creating a list makes the owner its first follower" do
    sign_in @alice

    post lists_path, params: { list: { name: "Tech", description: "People" } }
    list = List.last
    assert list.subscribed_by?(@alice)
    assert_equal 1, list.subscriber_count
  end

  test "a private list of another account cannot be followed" do
    list = List.create!(user: @bob, name: "Secret", is_private: true)

    sign_in @alice
    assert_no_difference -> { ListSubscription.count } do
      post list_follow_path(list)
    end
    assert_response :not_found
  end

  test "a private list of another account is not readable" do
    list = List.create!(user: @bob, name: "Secret", is_private: true)

    sign_in @alice
    get list_path(list)
    assert_response :not_found
  end

  test "a public list of another account is readable but not editable" do
    list = List.create!(user: @bob, name: "Public")

    sign_in @alice
    get list_path(list)
    assert_response :success

    get edit_list_path(list)
    assert_response :not_found
  end

  test "members can be added and removed by the owner only" do
    list = List.create!(user: @alice, name: "Friends")

    sign_in @alice
    post list_members_path(list), params: { username: "@bob" }
    assert_response :redirect
    assert list.reload.includes?(@bob)

    delete list_member_path(list, @bob)
    assert_response :redirect
    assert_not list.reload.includes?(@bob)

    sign_in @carol
    post list_members_path(list), params: { username: "@carol" }
    assert_response :not_found
  end

  # ------------------------------------------------------ follow requests

  test "following a protected account creates a request, not a follow" do
    @bob.update!(protected: true)

    sign_in @alice
    post follow_user_path(@bob.username)

    assert FollowRequest.pending.exists?(requester: @alice, target: @bob)
    assert_not Follow.exists?(follower_id: @alice.id, followee_id: @bob.id)
  end

  test "the target approves a request and the follow is created" do
    @bob.update!(protected: true)
    request = FollowRequest.create!(requester: @alice, target: @bob)

    sign_in @bob
    get follow_requests_path
    assert_response :success
    assert_match "@alice", response.body

    post approve_follow_request_path(request)
    assert_response :redirect

    assert Follow.exists?(follower_id: @alice.id, followee_id: @bob.id)
    assert_equal "approved", request.reload.state
  end

  test "rejecting a request leaves no follow behind" do
    @bob.update!(protected: true)
    request = FollowRequest.create!(requester: @alice, target: @bob)

    sign_in @bob
    post reject_follow_request_path(request)
    assert_response :redirect

    assert_not Follow.exists?(follower_id: @alice.id, followee_id: @bob.id)
    assert_equal "rejected", request.reload.state
  end

  test "a request aimed at somebody else cannot be approved" do
    @bob.update!(protected: true)
    request = FollowRequest.create!(requester: @alice, target: @bob)

    sign_in @carol
    post approve_follow_request_path(request)
    assert_response :not_found
    assert_equal "pending", request.reload.state
  end

  # ------------------------------------------------- protected accounts

  test "a protected account's posts are hidden from a non-follower" do
    @bob.update!(protected: true)

    sign_in @alice
    get profile_path(@bob.username)
    assert_response :success
    assert_no_match "hello from bob", response.body

    # The permalink is a 404 rather than a page that renders and then has to
    # hide its own contents, so a stranger cannot confirm the post exists.
    get tweet_path(@post)
    assert_response :not_found
  end

  test "a protected account's posts are visible to an approved follower" do
    @bob.update!(protected: true)
    Follow.create!(follower_id: @alice.id, followee_id: @bob.id)

    sign_in @alice
    get profile_path(@bob.username)
    assert_response :success
    assert_match "hello from bob", response.body
  end

  test "a protected account can always read its own posts" do
    @bob.update!(protected: true)

    sign_in @bob
    get profile_path(@bob.username)
    assert_response :success
    assert_match "hello from bob", response.body
  end

  test "protecting an account from settings changes the setting" do
    sign_in @alice
    patch privacy_settings_path, params: { protected: "1" }

    assert_response :redirect
    assert @alice.reload.protected?
  end

  # -------------------------------------------------------- blocks/mutes

  test "blocking hides both accounts from each other and ends follows" do
    Follow.create!(follower_id: @alice.id, followee_id: @bob.id)

    sign_in @alice
    post block_user_path(@bob.username)
    assert_response :redirect

    assert @alice.blocking?(@bob)
    assert_not Follow.exists?(follower_id: @alice.id, followee_id: @bob.id)

    get home_path
    assert_no_match "hello from bob", response.body
  end

  test "a block hides the blocked account's posts from the blocker's timeline" do
    @post.update!(created_at: 1.minute.ago)
    Follow.create!(follower_id: @alice.id, followee_id: @bob.id)
    Block.create!(blocker_id: @bob.id, blocked_id: @alice.id)

    sign_in @alice
    get home_path
    assert_no_match "hello from bob", response.body
  end

  test "unblocking restores visibility" do
    @alice.block!(@bob)

    sign_in @alice
    delete block_user_path(@bob.username)
    assert_response :redirect

    assert_not @alice.blocking?(@bob)
  end

  test "muting hides the muted account from the muter only" do
    Follow.create!(follower_id: @alice.id, followee_id: @bob.id)

    sign_in @alice
    post mute_user_path(@bob.username)
    assert_response :redirect
    assert @alice.muting?(@bob)

    get home_path
    assert_no_match "hello from bob", response.body

    # The muted account still sees the muter's posts; a mute is one-way.
    @bob_follow = Follow.create!(follower_id: @bob.id, followee_id: @alice.id)
    Tweet.create!(user: @alice, body: "hello from alice")

    sign_in @bob
    get home_path
    assert_match "hello from alice", response.body
  end

  test "an account cannot block or mute itself" do
    sign_in @alice

    post block_user_path(@alice.username)
    assert_response :redirect
    assert_not @alice.blocking?(@alice)

    post mute_user_path(@alice.username)
    assert_response :redirect
    assert_not @alice.muting?(@alice)
  end

  # -------------------------------------------------------------- reports

  test "a post can be reported and lands in the moderation queue" do
    sign_in @alice

    get new_report_path, params: { tweet_id: @post.id }
    assert_response :success

    assert_difference -> { Report.count }, 1 do
      post report_path, params: { tweet_id: @post.id, category: "spam", detail: "junk" }
    end

    report = Report.last
    assert_equal @alice.id, report.reporter_id
    assert_equal @post.user_id, report.user_id
    assert_equal @post.id, report.tweet_id
    assert_equal "open", report.state
  end

  test "an account can be reported" do
    sign_in @alice

    assert_difference -> { Report.count }, 1 do
      post report_path, params: { username: @bob.username, category: "impersonation" }
    end

    assert_equal @bob.id, Report.last.user_id
  end

  test "a report with no reason is refused" do
    sign_in @alice

    assert_no_difference -> { Report.count } do
      post report_path, params: { tweet_id: @post.id }
    end

    assert_response :unprocessable_entity
  end

  test "the reporter is always the signed-in account, never the request" do
    sign_in @alice

    post report_path, params: { tweet_id: @post.id, category: "spam", reporter_id: @carol.id }

    assert_equal @alice.id, Report.last.reporter_id
  end

  # --------------------------------------------------------- quote tweets

  test "a post can be quoted and both bodies show" do
    sign_in @alice

    # Quoting starts from the quoted post's permalink, which renders the
    # composer with that post attached.
    get tweet_path(@post), params: { quote: 1 }
    assert_response :success

    assert_difference -> { Tweet.count }, 1 do
      post compose_path, params: { body: "look at this", quote_of_id: @post.id }
    end

    quote = Tweet.last
    assert_equal @post.id, quote.quote_of_id

    get tweet_path(quote)
    assert_response :success
    assert_match "look at this", response.body
    assert_match "hello from bob", response.body
  end

  test "quoting notifies the quoted post's author" do
    sign_in @alice

    assert_difference -> { Notification.count }, 1 do
      post compose_path, params: { body: "quoting you", quote_of_id: @post.id }
    end

    assert_equal "quote", Notification.last.kind
    assert_equal @bob.id, Notification.last.user_id
  end

  test "an empty quote is allowed and shows only the quoted post" do
    sign_in @alice

    # Quoting without a comment was permitted by the 2019 client: the post
    # carried the quoted card and no body of its own.
    assert_difference -> { Tweet.count }, 1 do
      post compose_path, params: { body: "", quote_of_id: @post.id }
    end

    quote = Tweet.last
    assert_equal @post.id, quote.quote_of_id
    assert_equal "", quote.body.to_s
  end

  test "an empty post that quotes nothing is refused" do
    sign_in @alice

    assert_no_difference -> { Tweet.count } do
      post compose_path, params: { body: "" }
    end
  end

  test "a quote cannot attach a post the reader may not see" do
    @bob.update!(protected: true)

    sign_in @alice
    assert_no_difference -> { Tweet.count } do
      post compose_path, params: { body: "sneaking a look", quote_of_id: @post.id }
    end
  end

  # ------------------------------------------------------- quote tweets list

  # 2019's permalink count line linked "Quote Tweets" to a screen of the quotes
  # themselves. The figure is only useful if it opens that list.
  test "the permalink quote figure links to the quotes screen" do
    sign_in @alice

    get tweet_path(@post)
    assert_response :success
    assert_select "a.stat-quote[href=?]", tweet_quotes_path(@post)

    get tweet_quotes_path(@post)
    assert_response :success
    assert_match "Quote Tweets", response.body
    # The source post leads the list, so the reader knows what is being quoted.
    assert_match "hello from bob", response.body
  end

  test "the quotes screen lists the posts that quote this one" do
    quote = Tweet.create!(user: @carol, body: "worth quoting", quote_of: @post)

    sign_in @alice
    get tweet_quotes_path(@post)
    assert_response :success
    assert_match "worth quoting", response.body
    assert_select "li.tweet[data-tweet=?]", quote.id
  end

  test "an unquoted post shows the 2019 empty state" do
    sign_in @alice

    get tweet_quotes_path(@post)
    assert_response :success
    assert_match "No Quote Tweets yet", response.body
    assert_select ".empty-state .empty-state-icon"
  end

  # The count answers "how many", the list answers "which ones you may read", so
  # a quote by a blocked account is withheld from the list without changing the
  # figure on the permalink.
  test "a quote from a blocked account is withheld from the quotes list" do
    Tweet.create!(user: @carol, body: "hidden quote", quote_of: @post)
    @alice.block!(@carol)

    sign_in @alice
    get tweet_quotes_path(@post)
    assert_response :success
    assert_no_match "hidden quote", response.body
    assert_match "No Quote Tweets yet", response.body
  end

  test "a quote by a permanently banned account is withheld from the quotes list" do
    Tweet.create!(user: @carol, body: "banned quote", quote_of: @post)
    @carol.update!(is_banned: true, ban_permanent: true)

    sign_in @alice
    get tweet_quotes_path(@post)
    assert_response :success
    assert_no_match "banned quote", response.body
  end

  test "the quotes screen requires a signed-in account" do
    get tweet_quotes_path(@post)
    assert_response :redirect
  end

  # -------------------------------------------------------- hidden replies

  test "the parent's author can hide a reply from everyone but themselves" do
    reply = Tweet.create!(user: @carol, body: "a reply", parent_id: @post.id)

    sign_in @bob
    post hide_reply_path(reply)
    assert_response :redirect
    assert reply.reload.reply_hidden?

    # The author still sees it, marked as hidden.
    get tweet_path(@post)
    assert_response :success
    assert_match "a reply", response.body

    # Everybody else does not.
    sign_in @alice
    get tweet_path(@post)
    assert_response :success
    assert_no_match "a reply", response.body
  end

  test "a reply can be unhidden" do
    reply = Tweet.create!(user: @carol, body: "a reply", parent_id: @post.id)
    reply.hide_reply!

    sign_in @bob
    delete hide_reply_path(reply)
    assert_response :redirect
    assert_not reply.reload.reply_hidden?

    sign_in @alice
    get tweet_path(@post)
    assert_match "a reply", response.body
  end

  test "only the parent's author can hide a reply" do
    reply = Tweet.create!(user: @carol, body: "a reply", parent_id: @post.id)

    sign_in @alice
    post hide_reply_path(reply)
    assert_response :redirect
    assert_not reply.reload.reply_hidden?
  end

  # ------------------------------------------------------------- activity

  test "the author can read a post's activity" do
    sign_in @bob

    get tweet_activity_path(@post)
    assert_response :success
  end

  test "another account cannot read a post's activity" do
    sign_in @alice

    get tweet_activity_path(@post)
    assert_response :redirect
  end

  # --------------------------------------------------------- misc pages

  test "the lists index renders for a signed-in account" do
    sign_in @alice
    get lists_path
    assert_response :success
  end

  test "the follow requests page renders" do
    sign_in @alice
    get follow_requests_path
    assert_response :success
  end

  test "notifications can be filtered to mentions" do
    Notification.create!(user: @alice, actor: @bob, kind: "mention", body: "hey @alice")
    Notification.create!(user: @alice, actor: @bob, kind: "follow", body: "followed you")

    sign_in @alice
    get notifications_path(tab: "mentions")
    assert_response :success
    assert_match "hey @alice", response.body
    assert_no_match "followed you", response.body
  end
end
