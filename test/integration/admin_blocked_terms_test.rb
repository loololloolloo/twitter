require "test_helper"

# Covers the blocked-terms list and the two modes it can hold. The mode is the
# whole point of the feature: a "flag" term must leave its posts where they
# are, and a "hide" term must take them out of every timeline. These tests
# check both effects against real timelines, that the screen states each effect
# in plain words, and that changing the list is gated on its own permission.
class AdminBlockedTermsTest < ActionDispatch::IntegrationTest
  setup do
    # The matcher is cached across requests, so each test starts from a clean
    # compile rather than inheriting whatever the previous test left behind.
    BlockedTerm.invalidate_matcher!
  end

  def create_tweet(user, body)
    Tweet.create!(user: user, body: body)
  end

  test "the owner sees the list with each mode's effect stated plainly" do
    owner = create_user(username: "king", role: "owner")
    member = create_user(username: "member")
    BlockedTerm.create!(term: "shadowban", mode: "hide", category: "spam")
    BlockedTerm.create!(term: "scam", mode: "flag", category: "spam")
    create_tweet(member, "this mentions scam")

    sign_in(owner)
    get admin_blocked_terms_path

    assert_response :success
    assert_match(/Blocked terms/, response.body)
    # The two blast radii are spelled out, not left to the mode label.
    assert_match(/removes every matching post from every timeline/, response.body)
    assert_match(/leaves\s+the post where it is/, response.body)
    assert_match(/hides from every timeline/, response.body)
    assert_match(/flags for review, post stays up/, response.body)
    assert_match(/scam/, response.body)
  end

  test "a hide term removes matching posts from the visible timeline" do
    owner = create_user(username: "king", role: "owner")
    member = create_user(username: "member")
    hidden = create_tweet(member, "buy cheap widgets now")
    kept = create_tweet(member, "unrelated post")

    assert_includes Tweet.visible, kept

    BlockedTerm.create!(term: "cheap widgets", mode: "hide", category: "spam")

    refute_includes Tweet.visible, hidden, "a hide term must drop the post from every timeline"
    assert_includes Tweet.visible, kept, "a hide term must not touch unrelated posts"
  end

  test "a flag term leaves the post visible and lists it for review" do
    owner = create_user(username: "king", role: "owner")
    member = create_user(username: "member")
    flagged = create_tweet(member, "possible scam here")
    create_tweet(member, "ordinary post")

    BlockedTerm.create!(term: "scam", mode: "flag", category: "spam")

    assert_includes Tweet.visible, flagged, "a flag term must leave the post up"
    assert_equal [ flagged.id ], Tweet.matching_flags.pluck(:id)

    sign_in(owner)
    get admin_blocked_terms_path

    assert_response :success
    assert_match(/possible scam here/, response.body)
    assert_no_match(/ordinary post/, response.body)
  end

  test "matching is case-insensitive and does not treat wildcards as patterns" do
    owner = create_user(username: "king", role: "owner")
    member = create_user(username: "member")
    mixed = create_tweet(member, "Banned Phrase in caps")
    literal = create_tweet(member, "100% genuine")
    other = create_tweet(member, "something else entirely")

    BlockedTerm.create!(term: "banned phrase", mode: "hide", category: "abuse")

    refute_includes Tweet.visible, mixed, "matching must ignore case"
    assert_includes Tweet.visible, other

    # A literal "%" in the term is escaped, so a term of "100%" must not behave
    # like the SQL pattern "%" and swallow every post on the site.
    BlockedTerm.create!(term: "100%", mode: "hide", category: "spam")
    refute_includes Tweet.visible, literal
    assert_includes Tweet.visible, other
  end

  test "the term count reports the posts a hide term is already hiding" do
    owner = create_user(username: "king", role: "owner")
    member = create_user(username: "member")
    create_tweet(member, "one forbidden thing")
    create_tweet(member, "another forbidden thing")
    create_tweet(member, "harmless")

    term = BlockedTerm.create!(term: "forbidden", mode: "hide", category: "abuse")

    assert_equal 2, term.matching_post_count
    assert_equal [ "harmless" ], Tweet.visible.pluck(:body)
  end

  test "the list shows the exact match count, not a compacted one" do
    owner = create_user(username: "king", role: "owner")
    member = create_user(username: "member")
    1_200.times { |i| create_tweet(member, "bulk spam #{i}") }

    BlockedTerm.create!(term: "bulk spam", mode: "flag", category: "spam")

    sign_in(owner)
    get admin_blocked_terms_path
    assert_response :success

    # Scoped to the term's own row: the nav rail legitimately shows compacted
    # counts elsewhere, so a page-wide assertion would test the wrong thing.
    row = response.body[/<tr[^>]*>(?:(?!<\/tr>).)*bulk spam.*?<\/tr>/m]
    assert_not_nil row, "expected a row for the term"
    # "1.2K" would hide the blast radius this column exists to show.
    assert_match(/>1,200</, row)
    assert_no_match(/>1\.2K</, row)
  end

  test "the add form defaults to the flag mode, not the destructive hide" do
    owner = create_user(username: "king", role: "owner")
    sign_in(owner)

    get admin_blocked_terms_path
    assert_response :success

    flag_option = response.body[/<option value="flag"[^>]*>/]
    hide_option = response.body[/<option value="hide"[^>]*>/]
    assert_match(/selected/, flag_option.to_s)
    refute_match(/selected/, hide_option.to_s)
  end

  test "turning a term off restores the posts and keeps the row for the audit trail" do
    owner = create_user(username: "king", role: "owner")
    member = create_user(username: "member")
    hidden = create_tweet(member, "term to toggle")
    term = BlockedTerm.create!(term: "toggle", mode: "hide", category: "other")

    refute_includes Tweet.visible, hidden

    sign_in(owner)
    post admin_blocked_term_toggle_path(term)
    assert_redirected_to admin_blocked_terms_path

    term.reload
    refute term.active
    assert_includes Tweet.visible, hidden, "turning the term off must restore the posts"
    assert AuditLog.exists?(action: "settings.blocked_terms", target: "blocked_term:#{term.id}")
  end

  test "adding a term is audited and rejects a duplicate case-insensitively" do
    owner = create_user(username: "king", role: "owner")
    sign_in(owner)

    post admin_blocked_terms_path, params: { term: "Spam Link", mode: "hide", category: "spam" }
    assert_redirected_to admin_blocked_terms_path

    term = BlockedTerm.find_by(term: "Spam Link")
    refute_nil term
    assert_equal "hide", term.mode
    assert_equal owner.id, term.created_by_id
    assert AuditLog.exists?(action: "settings.blocked_terms", target: "blocked_term:#{term.id}")

    post admin_blocked_terms_path, params: { term: "spam link", mode: "flag", category: "spam" }
    assert_redirected_to admin_blocked_terms_path
    assert_equal 1, BlockedTerm.where("LOWER(term) = ?", "spam link").count
  end

  test "a moderator can read the list but cannot change it" do
    moderator = create_user(username: "mod", role: "moderator")
    sign_in(moderator)

    get admin_blocked_terms_path
    assert_response :success

    assert_no_difference "BlockedTerm.count" do
      post admin_blocked_terms_path, params: { term: "nope", mode: "hide", category: "spam" }
    end
    assert_redirected_to admin_root_path
    assert_match(/settings\.blocked_terms/, flash[:alert].to_s)
  end

  test "a plain member cannot reach the list at all" do
    member = create_user(username: "member")
    sign_in(member)

    get admin_blocked_terms_path
    assert_redirected_to home_path
  end
end
