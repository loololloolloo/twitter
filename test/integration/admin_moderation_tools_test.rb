require "test_helper"

# Covers the two features the permission registry already advertised but that
# had no implementation: the report queue behind reports.view / reports.resolve,
# and pinning behind tweets.pin. Also covers the operational tags that the
# redesigned user page writes, since they are the part of that page with real
# behaviour behind them.
class AdminModerationToolsTest < ActionDispatch::IntegrationTest
  test "the report queue renders for an operator holding reports.view" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")
    Report.create!(user: target, reporter: owner, category: "abuse", detail: "harassment")

    sign_in(owner)
    get admin_reports_path
    assert_response :success
    assert_match(/harassment/, response.body)
    assert_match(/member/, response.body)
  end

  test "resolving a report closes it and records the decision" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")
    report = Report.create!(user: target, reporter: owner, category: "spam", detail: "advertising")

    sign_in(owner)
    post admin_report_resolve_path(report), params: { decision: "actioned", note: "removed" }

    assert_redirected_to admin_reports_path
    report.reload
    assert_equal "actioned", report.state
    assert_equal "removed", report.resolution_note
    assert_equal owner.id, report.resolved_by_id
    assert report.resolved_at.present?
    assert Report.open.count.zero?
  end

  test "a moderator can view and resolve reports" do
    moderator = create_user(username: "mod", role: "moderator")
    target = create_user(username: "member")
    report = Report.create!(user: target, category: "hate")

    sign_in(moderator)
    get admin_reports_path
    assert_response :success

    post admin_report_resolve_path(report), params: { decision: "dismissed" }
    assert_equal "dismissed", report.reload.state
  end

  test "a role without reports.view is turned away from the queue" do
    member = create_user(username: "member", role: "user")

    sign_in(member)
    get admin_reports_path
    assert_redirected_to home_path
  end

  test "a resolved report cannot be resolved twice" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")
    report = Report.create!(user: target, category: "abuse")
    report.resolve!(state: "dismissed", actor: owner)

    sign_in(owner)
    post admin_report_resolve_path(report), params: { decision: "actioned" }

    assert_redirected_to admin_reports_path
    assert_equal "dismissed", report.reload.state
  end

  test "tagging a user records the flags and the note" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")

    sign_in(owner)
    post admin_user_tags_path(target), params: {
      search_blacklist: "1", trends_blacklist: "1", requires_review: "1",
      review_reason: "possible coordinated inauthentic behaviour",
      tag_note: "under review"
    }

    assert_redirected_to admin_user_path(target)
    target.reload
    assert target.search_blacklist
    assert target.trends_blacklist
    assert target.requires_review
    assert target.elevated_handling?
    refute target.do_not_amplify
    assert_equal "under review", target.tag_note
    assert_equal "possible coordinated inauthentic behaviour", target.review_reason
    assert_includes target.account_tags, "Search Blacklist"
    assert target.reach_limited?
  end

  test "routing an account to elevated review without a reason is refused" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")

    sign_in(owner)
    post admin_user_tags_path(target), params: { requires_review: "1", review_reason: "  " }

    assert_redirected_to admin_user_path(target)
    refute target.reload.requires_review, "the flag must not be raised without a reason"
    assert_equal "", target.review_reason
  end

  test "the reason survives a later tag edit and is cleared when the flag is lowered" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")
    target.update!(requires_review: true, review_reason: "insider risk")

    sign_in(owner)

    # An unrelated reach toggle, submitted with an empty reason field, must not
    # wipe the reason recorded for the flag.
    post admin_user_tags_path(target), params: {
      search_blacklist: "1", requires_review: "1", review_reason: ""
    }
    assert_equal "insider risk", target.reload.review_reason

    post admin_user_tags_path(target), params: { search_blacklist: "1" }
    refute target.reload.requires_review
    assert_equal "", target.review_reason
  end

  test "the caution strip carries the recorded reason above the controls" do
    owner = create_user(username: "king", role: "owner")
    flagged = create_user(username: "flagged")
    flagged.update!(requires_review: true, review_reason: "elevated by policy")

    sign_in(owner)
    get admin_user_path(flagged)

    assert_response :success
    assert_match(/elevated by policy/, response.body)
    # The banner is the first thing on the page, above the action controls.
    assert response.body.index(/Consulting SIP-PES/) < response.body.index(/Save tags/),
           "the caution banner must sit above the action controls"
  end

  test "clearing a tag turns it off" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")
    target.update!(search_blacklist: true, trends_blacklist: true)

    sign_in(owner)
    post admin_user_tags_path(target), params: { trends_blacklist: "1", tag_note: "" }

    target.reload
    refute target.search_blacklist, "an unchecked flag should be cleared"
    assert target.trends_blacklist
  end

  test "the caution strip appears only for an account tagged for review" do
    owner = create_user(username: "king", role: "owner")
    calm = create_user(username: "calm")
    flagged = create_user(username: "flagged")
    flagged.update!(requires_review: true)

    sign_in(owner)

    get admin_user_path(calm)
    assert_response :success
    refute_match(/Consulting SIP-PES/, response.body)

    get admin_user_path(flagged)
    assert_response :success
    assert_match(/Consulting SIP-PES/, response.body)
  end

  test "pinning a tweet puts it on the author's profile and unpinning removes it" do
    owner = create_user(username: "king", role: "owner")
    author = create_user(username: "author")
    tweet = author.tweets.create!(body: "pin me")

    sign_in(owner)
    post admin_tweet_pin_path(tweet)

    assert_redirected_to admin_tweets_path
    assert tweet.reload.pinned_at.present?

    get profile_path(author.username)
    assert_match(/Pinned Tweet/, response.body)

    post admin_tweet_unpin_path(tweet)
    refute tweet.reload.pinned_at.present?
  end

  test "pinning a second tweet replaces the first" do
    owner = create_user(username: "king", role: "owner")
    author = create_user(username: "author")
    first = author.tweets.create!(body: "first")
    second = author.tweets.create!(body: "second")

    sign_in(owner)
    post admin_tweet_pin_path(first)
    post admin_tweet_pin_path(second)

    refute first.reload.pinned_at.present?
    assert second.reload.pinned_at.present?
  end
end