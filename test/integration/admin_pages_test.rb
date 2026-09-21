require "test_helper"

# Walks every screen in the admin area as an owner, and checks that a
# moderator without the matching grants is turned away from the pages they do
# not own. The dashboard's own links are followed so a renamed helper or route
# shows up here rather than on the live site.
class AdminPagesTest < ActionDispatch::IntegrationTest
  OWNER_PAGES = %w[
    /admin
    /admin/users
    /admin/permissions
    /admin/settings
    /admin/blocked-terms
    /admin/tweets
    /admin/audit
    /admin/insights
    /admin/tools
    /admin/lookup
    /admin/escalations
    /admin/appeals
    /admin/verification
    /admin/sessions
    /admin/relations
    /admin/lists
  ].freeze

  test "every admin page renders for the owner" do
    owner = create_user(username: "king", role: "owner")
    create_user(username: "member")
    sign_in(owner)

    OWNER_PAGES.each do |path|
      get path
      assert_response :success, "#{path} did not render"
    end
  end

  test "the insights screen reports totals and storage" do
    owner = create_user(username: "king", role: "owner")
    member = create_user(username: "member")
    tweet = Tweet.create!(user: member, body: "counted", bonus_likes: 4)
    Like.create!(user: owner, tweet: tweet, kind: "like")

    sign_in(owner)
    get admin_insights_path

    assert_response :success
    assert_match(/Insights/, response.body)
    assert_match(/New accounts, last 14 days/, response.body)
    assert_match(/Most followed/, response.body)
    assert_match(/Most liked posts/, response.body)
    assert_match(/Storage/, response.body)
  end

  test "the user detail page renders for the owner" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")
    sign_in(owner)

    get admin_user_path(target)
    assert_response :success
    assert_match(/member/, response.body)
  end

  test "a moderator only reaches the pages they hold permissions for" do
    moderator = create_user(username: "mod", role: "moderator")
    sign_in(moderator)

    # Granted: admin.access, users.view, tweets.view
    get admin_root_path
    assert_response :success

    get admin_users_path
    assert_response :success

    get admin_tweets_path
    assert_response :success

    # Not granted: audit, backup, settings, permissions, sessions
    [ admin_audit_path, admin_settings_path, admin_permissions_path,
      admin_sessions_path, admin_relations_path, admin_lists_path ].each do |path|
      get path
      assert_redirected_to admin_root_path, "#{path} should be refused for a moderator"
    end

    # Granted to a moderator: the lookup and escalation surfaces, which are the
    # read-only tools a front-line reviewer needs, plus the appeals queue they
    # work decisions from.
    [ admin_lookup_path, admin_escalations_path, admin_appeals_path,
      admin_verification_path ].each do |path|
      get path
      assert_response :success, "#{path} should be reachable for a moderator"
    end
  end

  test "the audit log records admin actions and can be searched" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")
    sign_in(owner)

    post admin_user_verified_path(target)
    assert AuditLog.exists?(action: "users.verify")

    get admin_audit_path(q: "users.verify")
    assert_response :success
    assert_match(/users\.verify/, response.body)
  end

  test "site settings round-trip through the form" do
    owner = create_user(username: "king", role: "owner")
    sign_in(owner)

    post admin_settings_path, params: {
      site_name: "Chirper", site_tagline: "Go on then", max_tweet_length: "280"
    }

    assert_redirected_to admin_settings_path
    assert_equal "Chirper", SiteSetting.get("site_name")
    assert_equal "280", SiteSetting.get("max_tweet_length")
  end

  test "an unchecked registration box closes signups" do
    owner = create_user(username: "king", role: "owner")
    sign_in(owner)

    post admin_settings_path, params: { site_name: "Twitter", site_tagline: "Hi", max_tweet_length: "140" }

    assert_equal "0", SiteSetting.get("registration_open")
    refute SiteSetting.registration_open?
  end

  test "permissions can be regranted to a role but never stripped from the owner" do
    owner = create_user(username: "king", role: "owner")
    sign_in(owner)

    moderator = Role.find_by!(name: "moderator")
    post admin_permissions_path, params: {
      role_id: moderator.id, permissions: %w[admin.access users.view tweets.view users.ban]
    }

    assert_equal %w[admin.access tweets.view users.ban users.view],
                 moderator.reload.permissions.map(&:key).sort

    # The owner role is protected from edits.
    owner_role = Role.find_by!(name: "owner")
    post admin_permissions_path, params: { role_id: owner_role.id, permissions: [] }
    assert_equal Permission.count, owner_role.reload.permissions.count
  end

  test "the backup export streams a SQL dump" do
    owner = create_user(username: "king", role: "owner")
    sign_in(owner)

    get admin_backup_path
    assert_response :success
    assert_match(/attachment/, response.headers["Content-Disposition"])
    assert_match(/CREATE TABLE/, response.body)
    assert_match(/INSERT INTO users/, response.body)
  end

  test "a tweet can be removed from the admin tweet list" do
    owner = create_user(username: "king", role: "owner")
    author = create_user(username: "author")
    tweet = Tweet.create!(user: author, body: "Something regrettable")
    sign_in(owner)

    delete admin_tweet_path(tweet)

    # Deletion is a soft delete: the row survives for the audit trail and for
    # replies, but it is gone from every visible timeline.
    assert tweet.reload.is_deleted
    refute Tweet.visible.exists?(tweet.id)
    assert AuditLog.exists?(action: "tweets.delete", target: "tweet:#{tweet.id}")
  end
end