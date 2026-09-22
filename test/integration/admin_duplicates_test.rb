require "test_helper"

# The duplicate-account screen and the cluster builder behind it. The point of
# the feature is that it reports shared signup signals as a hint and changes
# nothing, so the tests care about what the operator can see and about the
# absence of any enforcement side effect.
class AdminDuplicatesTest < ActionDispatch::IntegrationTest
  test "accounts sharing a mailbox name are shown as one cluster" do
    owner = create_user(username: "king", role: "owner")
    first = create_user(username: "spamden", email: "spamden.1@example.com")
    second = create_user(username: "spamfan", email: "spamden.2@example.com")

    sign_in(owner)
    get admin_duplicates_path

    assert_response :success
    assert_match(/Duplicate accounts/, response.body)
    assert_match(/@spamden/, response.body)
    assert_match(/@spamfan/, response.body)
    assert_match(/Shared mailbox name/, response.body)
    assert_match(/spamden/, response.body)

    # A hint, not a verdict: reading the queue must not touch either account.
    [ first, second ].each do |account|
      account.reload
      assert_not account.is_banned
      assert_not account.is_suspended
      assert_not account.is_verified
    end
    assert_equal 0, AuditLog.where(action: "users.ban").count
  end

  test "accounts with nothing in common are not grouped" do
    owner = create_user(username: "king", role: "owner")
    create_user(username: "alice", email: "alice@example.com", created_at: 5.days.ago)
    create_user(username: "bob", email: "bob@other.test", created_at: 30.days.ago)

    sign_in(owner)
    get admin_duplicates_path

    assert_response :success
    assert_match(/No accounts currently share a signup signal/, response.body)
  end

  test "a shared signup window is reported with its detail" do
    owner = create_user(username: "king", role: "owner")
    create_user(username: "firstwave", email: "one@example.com", created_at: 3.hours.ago)
    create_user(username: "secondwave", email: "two@example.com", created_at: 3.hours.ago)

    sign_in(owner)
    get admin_duplicates_path

    assert_response :success
    assert_match(/Shared signup window/, response.body)
    assert_match(/accounts created within 15 minutes/, response.body)
  end

  test "a moderator without relations.view is refused" do
    moderator = create_user(username: "mod", role: "moderator")

    sign_in(moderator)
    get admin_duplicates_path

    assert_redirected_to admin_root_path
    follow_redirect!
    assert_match(/relations\.view/, response.body)
  end

  test "the builder merges overlapping signals into one cluster" do
    accounts = [
      create_user(username: "botalpha1", email: "ring.1@example.com", created_at: 2.hours.ago),
      create_user(username: "botalpha2", email: "ring.2@example.com", created_at: 2.hours.ago)
    ]

    clusters = SockpuppetCluster.new(User.where(id: accounts.map(&:id))).clusters

    assert_equal 1, clusters.size
    assert_equal 2, clusters.first.size
    assert_operator clusters.first.ordered_signals.size, :>=, 2
    assert_operator clusters.first.score, :>, 0
  end

  test "the builder needs two accounts before it reports anything" do
    lone = create_user(username: "solo", email: "solo@example.com")

    clusters = SockpuppetCluster.new(User.where(id: lone.id)).clusters

    assert_empty clusters
  end

  test "a plus-tagged address is one mailbox, not two" do
    create_user(username: "tagger", email: "same+news@example.com")
    create_user(username: "tagged", email: "same+alerts@example.com")

    clusters = SockpuppetCluster.new(User.all).clusters

    assert_equal 1, clusters.size
    assert_equal 2, clusters.first.size
  end
end
