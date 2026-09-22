require "test_helper"

# A permanently banned account must not leak any of its information through its
# profile. A timed ban is a different thing and keeps a normal profile.
class BannedProfileTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user(username: "owner_one", role: "owner")
    @viewer = create_user(username: "viewer_one")
    sign_in(@owner)
  end

  def make_banned(attrs = {})
    user = create_user(
      username: "banned_prof",
      display_name: "Bad Faith Actor",
      bio: "SECRET BIO",
      location: "SECRET LOCATION",
      website: "https://secret.example.com",
      is_verified: true,
      is_banned: true,
      ban_permanent: true,
      ban_reason: "testing"
    )
    user.update!(**attrs) if attrs.any?
    user
  end

  test "a permanently banned profile shows a notice instead of details" do
    user = make_banned
    Tweet.create!(user: user, body: "SECRET TWEET")

    get profile_path(user.username)

    assert_response :success
    assert_match(/Account permanently banned/, response.body)
    refute_match(/Bad Faith Actor/, response.body)
    refute_match(/SECRET BIO/, response.body)
    refute_match(/SECRET LOCATION/, response.body)
    refute_match(/secret\.example\.com/, response.body)
    refute_match(/SECRET TWEET/, response.body)
    refute_match(/verified-badge/, response.body)
  end

  test "a permanently banned profile falls back to the default picture" do
    user = make_banned
    user.update!(avatar_path: "avatars/real.png")

    get profile_path(user.username)

    assert_response :success
    assert_match(/avatar-empty/, response.body)
    refute_match(%r{/uploads/avatars/real\.png}, response.body)
  end

  test "a permanently banned profile offers no follow or message action" do
    user = make_banned

    get profile_path(user.username)

    assert_response :success
    refute_match(/btn-follow/, response.body)
    refute_match(/btn-msg/, response.body)
  end

  test "a permanently banned profile shows no counts or tabs" do
    user = make_banned

    get profile_path(user.username)

    assert_response :success
    refute_match(/profile-tabs/, response.body)
  end

  test "following and followers are not enumerable for a banned account" do
    user = make_banned
    other = create_user(username: "other_one")
    Follow.create!(follower: other, followee: user)
    Follow.create!(follower: user, followee: other)

    get following_path(user.username)
    assert_redirected_to profile_path(user.username)

    get followers_path(user.username)
    assert_redirected_to profile_path(user.username)
  end

  test "a timed ban still shows a normal profile" do
    user = create_user(
      username: "timed_ban",
      display_name: "Timed Person",
      bio: "still visible",
      is_banned: true,
      ban_permanent: false,
      ban_expires_at: 3.days.from_now
    )

    get profile_path(user.username)

    assert_response :success
    assert_match(/still visible/, response.body)
    assert_match(/Timed Person/, response.body)
    assert_match(/profile-tabs/, response.body)
    refute_match(/Account permanently banned/, response.body)
  end

  test "an unbanned account is untouched" do
    user = create_user(username: "normal_one", display_name: "Normal Person", bio: "hello")

    get profile_path(user.username)

    assert_response :success
    assert_match(/hello/, response.body)
    assert_match(/Normal Person/, response.body)
  end

  test "permanently_banned? is false for a timed ban and an active account" do
    timed = create_user(username: "timed_two", is_banned: true, ban_permanent: false,
                        ban_expires_at: 1.day.from_now)
    active = create_user(username: "active_two")

    refute timed.permanently_banned?
    refute active.permanently_banned?
  end

  test "permanently_banned? is true for a permanent ban" do
    user = create_user(username: "perm_two", is_banned: true, ban_permanent: true)

    assert user.permanently_banned?
  end

  test "a permanently banned account's tweets leave the timeline scope" do
    user = make_banned
    Tweet.create!(user: user, body: "SECRET TWEET")

    refute Tweet.visible.where(user_id: user.id).exists?
  end

  test "tweets from a timed-banned account stay visible" do
    user = create_user(username: "timed_three", is_banned: true, ban_permanent: false,
                       ban_expires_at: 1.day.from_now)
    tweet = Tweet.create!(user: user, body: "still around")

    assert Tweet.visible.exists?(tweet.id)
  end

  test "the owner can permanently ban a user through the admin form, with a second operator" do
    victim = create_user(username: "victim_one", display_name: "Victim Person",
                         bio: "VICTIM BIO")
    approver = create_user(username: "approver_one", role: "owner")

    # A permanent ban is four-eyes: the owner files it, a different owner
    # approves it, and only then does the account change.
    post admin_user_ban_path(victim), params: { reason: "investigation", duration: "permanent" }

    assert_response :redirect
    refute victim.reload.is_banned

    request = ApprovalRequest.find_by!(user: victim, action_key: "permanent_ban")
    sign_in(approver)
    post admin_approval_decide_path(request), params: { decision: "approved" }

    victim.reload
    assert victim.is_banned
    assert victim.ban_permanent

    get profile_path(victim.username)
    assert_response :success
    refute_match(/VICTIM BIO/, response.body)
    refute_match(/Victim Person/, response.body)
    assert_match(/Account permanently banned/, response.body)
  end

  test "the owner can set an advertised follower count" do
    user = create_user(username: "famous_one")

    post admin_user_followers_path(user), params: { followers: "12345" }

    assert_response :redirect
    assert_equal 12345, user.reload.follower_count
  end
end