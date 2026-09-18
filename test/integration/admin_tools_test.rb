require "test_helper"

# The maintenance screen destroys data, so these tests exercise the real
# database: every sweep is run against rows created here and the assertions
# count what survives.
class AdminToolsTest < ActionDispatch::IntegrationTest
  setup do
    RoleBootstrapper.run
    @owner = create_user(username: "tools_owner", role: "owner")
    @member = create_user(username: "tools_member", role: "user")
    @bot = create_user(username: "tools_bot", role: "user", is_bot: true)
    sign_in(@owner)
  end

  test "the tools screen renders its tabs and inventory" do
    get admin_tools_path
    assert_response :success
    assert_match(/Site tools/, response.body)
    assert_match(/Danger zone/, response.body)
    assert_match(/Backup &amp; restore/, response.body)
    assert_match(/Announcement/, response.body)
    assert_match(/Simulated accounts/, response.body)
  end

  test "the panel rail is a sidebar that does not repeat the top bar" do
    get admin_tools_path
    assert_match(/class="admin-rail"/, response.body)
    # The rail carries counts and shortcuts, not the section links, which live
    # in the top bar alone. Duplicating them was the bug this guards.
    assert_match(/class="rail-block"/, response.body)
    assert_match(/At a glance/, response.body)
    assert_match(/Quick actions/, response.body)
    refute_match(/class="admin-nav"/, response.body)
  end

  test "a destructive task is refused without the confirmation word" do
    Tweet.create!(user: @member, body: "keep me")

    post admin_tools_purge_tweets_path, params: { confirm: "nope" }

    assert_redirected_to admin_tools_path(tab: "site")
    assert_equal 1, Tweet.count
  end

  test "purging tweets deletes posts and what pointed at them" do
    tweet = Tweet.create!(user: @member, body: "gone soon")
    Like.create!(user: @owner, tweet: tweet, kind: "like")
    TweetView.create!(user: @owner, tweet: tweet)
    Notification.create!(user: @member, actor: @owner, kind: "like", tweet: tweet)

    post admin_tools_purge_tweets_path, params: { confirm: "confirm" }

    assert_redirected_to admin_tools_path(tab: "site")
    assert_equal 0, Tweet.count
    assert_equal 0, Like.count
    assert_equal 0, TweetView.count
    assert_equal 0, Notification.count
  end

  test "clearing the follow graph leaves accounts and posts alone" do
    Follow.create!(follower: @member, followee: @owner)
    Follow.create!(follower: @bot, followee: @member)
    Tweet.create!(user: @member, body: "still here")

    post admin_tools_clear_follows_path, params: { confirm: "CONFIRM" }

    assert_equal 0, Follow.count
    assert_equal 3, User.count
    assert_equal 1, Tweet.count
  end

  test "clearing simulated accounts removes only the bots and their content" do
    Follow.create!(follower: @bot, followee: @member)
    Follow.create!(follower: @member, followee: @owner)
    bot_tweet = Tweet.create!(user: @bot, body: "bot noise")
    Like.create!(user: @bot, tweet: bot_tweet, kind: "like")
    Tweet.create!(user: @member, body: "human post")

    post admin_tools_clear_bots_path, params: { confirm: "confirm" }

    assert_nil User.find_by(username: "tools_bot")
    assert User.find_by(username: "tools_member")
    assert_equal 1, Tweet.count
    assert_equal "human post", Tweet.first.body
    assert_equal 1, Follow.count
  end

  test "clearing sessions signs everyone else out and keeps the operator" do
    Session.create!(user: @member, token: "member-token", expires_at: 1.day.from_now)
    Session.create!(user: @owner, token: "owner-token", expires_at: 1.day.from_now)

    post admin_tools_clear_sessions_path, params: { confirm: "confirm" }

    assert_equal 0, Session.where(user_id: @member.id).count
    assert_equal 1, Session.where(user_id: @owner.id).count
  end

  test "pruning removes rows that point at records that no longer exist" do
    # A stranded row cannot be produced through the models - the foreign keys
    # stop it - so it is inserted with enforcement off, which is the state a
    # restored dump or a bot sweep can leave behind. Rails' own helper is used
    # because the tests run inside a transaction, where a raw PRAGMA is a no-op.
    connection = ActiveRecord::Base.connection
    connection.disable_referential_integrity do
      connection.execute(
        "INSERT INTO follows (follower_id, followee_id, created_at, updated_at) " \
        "VALUES (#{@owner.id}, 999999, '2020-01-01 00:00:00', '2020-01-01 00:00:00')"
      )
    end

    assert_equal 1, Follow.where(followee_id: 999_999).count

    post admin_tools_prune_orphans_path

    assert_equal 0, Follow.where(followee_id: 999_999).count
  end

  test "resetting the site keeps the operator and the configuration" do
    Tweet.create!(user: @member, body: "wipe me")
    Follow.create!(follower: @member, followee: @owner)

    post admin_tools_reset_path, params: { confirm: "confirm" }

    assert_equal [ @owner.id ], User.pluck(:id)
    assert_equal 0, Tweet.count
    assert_equal 0, Follow.count
    # Configuration survives: the roles and permissions the panel depends on.
    assert Role.count.positive?
    assert Permission.count.positive?
  end

  test "restoring a backup replaces the data" do
    dump = <<~SQL
      DELETE FROM tweets;
      INSERT INTO tweets (id, user_id, body, created_at, updated_at) VALUES (42, #{@member.id}, 'from the dump', '2020-01-01 00:00:00', '2020-01-01 00:00:00');
    SQL

    upload = Rack::Test::UploadedFile.new(StringIO.new(dump), "text/plain", original_filename: "backup.sql")
    post admin_tools_restore_path, params: { backup: upload }

    assert_redirected_to admin_tools_path(tab: "backup")
    assert_equal [ "from the dump" ], Tweet.pluck(:body)
  end

  test "a malformed backup leaves the existing data untouched" do
    Tweet.create!(user: @member, body: "original")

    dump = "INSERT INTO no_such_table (id) VALUES (1);"
    upload = Rack::Test::UploadedFile.new(StringIO.new(dump), "text/plain", original_filename: "bad.sql")
    post admin_tools_restore_path, params: { backup: upload }

    assert_match(/Restore failed/, flash[:alert].to_s)
    assert_equal [ "original" ], Tweet.pluck(:body)
  end

  test "a member without the permission cannot reach the tools" do
    delete logout_path rescue nil
    sign_in(@member)

    get admin_tools_path
    assert_response :redirect
  end

  test "the maintenance sweep is written to the audit log" do
    post admin_tools_clear_follows_path, params: { confirm: "confirm" }

    entry = AuditLog.where(action: "maintenance.clear_follows").last
    assert entry, "expected the sweep to be audited"
    assert_equal @owner.id, entry.actor_id
  end

  test "clearing granted followers empties the padding but keeps real follows" do
    @member.update!(bonus_followers: 5_000)
    @bot.update!(bonus_followers: 250)
    Follow.create!(follower: @owner, followee: @member)

    post admin_tools_clear_granted_followers_path, params: { confirm: "CONFIRM" }

    assert_equal 0, User.sum(:bonus_followers)
    assert_equal 1, Follow.count
  end

  test "clearing granted engagement zeroes the padding but keeps real reactions" do
    tweet = Tweet.create!(user: @member, body: "popular", bonus_likes: 99, bonus_retweets: 7)
    Like.create!(user: @owner, tweet: tweet, kind: "like")

    post admin_tools_clear_granted_engagement_path, params: { confirm: "CONFIRM" }

    tweet.reload
    assert_equal 0, tweet.bonus_likes
    assert_equal 0, tweet.bonus_retweets
    assert_equal 1, tweet.likes.count
  end

  test "clearing notifications leaves the posts behind" do
    tweet = Tweet.create!(user: @member, body: "stay put")
    Notification.create!(user: @member, actor: @owner, kind: "like", tweet: tweet)

    post admin_tools_clear_notifications_path, params: { confirm: "CONFIRM" }

    assert_equal 0, Notification.count
    assert_equal 1, Tweet.count
  end

  test "clearing messages removes conversations too" do
    convo = DmConversation.create!(user_a: @owner, user_b: @member)
    DmMessage.create!(dm_conversation: convo, sender: @owner, body: "hello")

    post admin_tools_clear_messages_path, params: { confirm: "CONFIRM" }

    assert_equal 0, DmMessage.count
    assert_equal 0, DmConversation.count
    assert_equal 3, User.count
  end

  test "clearing reports empties the queue without touching accounts or posts" do
    tweet = Tweet.create!(user: @member, body: "reported")
    Report.create!(user: @member, reporter: @owner, tweet: tweet, category: "spam")

    post admin_tools_clear_reports_path, params: { confirm: "CONFIRM" }

    assert_equal 0, Report.count
    assert_equal 1, Tweet.count
    assert_equal 3, User.count
  end

  test "clearing every session signs the operator out too" do
    Session.create!(user: @member, token: "member-token", expires_at: 1.day.from_now)
    Session.create!(user: @owner, token: "owner-token", expires_at: 1.day.from_now)

    post admin_tools_clear_all_sessions_path, params: { confirm: "CONFIRM" }

    assert_equal 0, Session.count
    assert_redirected_to login_path
  end

  test "the storage tab reports the database size and table weights" do
    get admin_tools_path(tab: "storage")

    assert_response :success
    assert_match(/File size/, response.body)
    assert_match(/Rows/, response.body)
    assert_match(/Compact the database/, response.body)
  end

  test "the content tab offers the new cleanups" do
    get admin_tools_path(tab: "content")

    assert_response :success
    assert_match(/Clear notifications/, response.body)
    assert_match(/Delete direct messages/, response.body)
    assert_match(/Clear granted engagement/, response.body)
  end
end