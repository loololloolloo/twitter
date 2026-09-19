require "test_helper"

# The toolbar tabs are the panel's working tools, and they are a different set
# from the rail's navigation. These tests cover what each one shows and what it
# is allowed to change, since a lookup surface reads account records and a
# session screen can end someone else's login.
class AdminToolbarTest < ActionDispatch::IntegrationTest
  setup do
    RoleBootstrapper.run
    @owner = create_user(username: "toolbar_owner", role: "owner")
    sign_in(@owner)
  end

  test "lookup resolves an exact account id to the record" do
    target = create_user(username: "lookup_target")

    get admin_lookup_path, params: { q: target.id.to_s, source: "users" }

    assert_response :success
    assert_match(/Exact match/, response.body)
    assert_match(/@lookup_target/, response.body)
    assert_match(/user ##{target.id}/, response.body)
  end

  test "lookup matches an account by username without an exact id" do
    create_user(username: "findable")

    get admin_lookup_path, params: { q: "findable", source: "users" }

    assert_response :success
    assert_match(/@findable/, response.body)
  end

  test "lookup reports nothing when the term matches nothing" do
    get admin_lookup_path, params: { q: "no_such_account_anywhere", source: "users" }

    assert_response :success
    assert_match(/Nothing matched/, response.body)
  end

  test "lookup ends a session found by its token" do
    target = create_user(username: "session_owner")
    row = Session.issue(target)

    delete admin_session_path(row)

    assert_redirected_to admin_sessions_path
    assert_nil Session.find_by(id: row.id)
    assert AuditLog.exists?(action: "sessions.revoke", target: "user:#{target.id}")
  end

  test "escalations lists accounts tagged for review apart from the rest" do
    flagged = create_user(username: "escalated", requires_review: true)
    create_user(username: "ordinary")

    get admin_escalations_path

    assert_response :success
    assert_match(/@escalated/, response.body)
    assert_match(/SIP-PES/, response.body)
    refute_match(/@ordinary/, response.body)
  end

  test "escalations keeps visibility limits on their own tab" do
    limited = create_user(username: "limited", search_blacklist: true)

    get admin_escalations_path(tab: "limits")

    assert_response :success
    assert_match(/@limited/, response.body)
    assert_match(/Search Blacklist/, response.body)
  end

  test "sessions lists active logins and ends them all for one account" do
    target = create_user(username: "many_sessions")
    Session.issue(target)
    Session.issue(target)

    assert_equal 2, Session.where(user_id: target.id).count

    get admin_sessions_path
    assert_response :success
    assert_match(/@many_sessions/, response.body)

    post admin_session_revoke_user_path(target)

    assert_redirected_to admin_sessions_path
    assert_equal 0, Session.where(user_id: target.id).count
    assert AuditLog.exists?(action: "sessions.revoke_all", target: "user:#{target.id}")
  end

  test "relations reads the block graph in both directions" do
    left = create_user(username: "blocker_one")
    right = create_user(username: "blocked_one")
    Block.create!(blocker: left, blocked: right)

    get admin_relations_path(tab: "blocks")

    assert_response :success
    assert_match(/@blocker_one/, response.body)
    assert_match(/@blocked_one/, response.body)
  end

  test "relations filters by either account's handle" do
    left = create_user(username: "muter_one")
    right = create_user(username: "muted_one")
    Mute.create!(muter: left, muted: right)

    get admin_relations_path(tab: "mutes", q: "muted_one")

    assert_response :success
    assert_match(/@muted_one/, response.body)
  end

  test "lists shows the members and flips visibility" do
    owner = create_user(username: "list_owner")
    listing = List.create!(user: owner, name: "Watchlist", is_private: false)

    get admin_lists_path
    assert_response :success
    assert_match(/Watchlist/, response.body)

    patch admin_list_path(listing), params: { is_private: "1" }

    assert_redirected_to admin_lists_path
    assert listing.reload.is_private
    assert AuditLog.exists?(action: "lists.visibility", target: "list:#{listing.id}")
  end
end
