require "test_helper"

# The account tags the panel advertises as visibility limits used to be stored,
# audited and rendered without ever changing what a reader saw. These pin the
# three blast radii apart from each other: a search blacklist limits discovery
# only, a trends blacklist limits trends only, and do-not-amplify keeps an
# author's reach away from every reader but the author.
class ReachLimitEnforcementTest < ActionDispatch::IntegrationTest
  setup do
    @me = create_user(username: "reach_me")
    @limited = create_user(username: "reach_limited")
    sign_in @me
  end

  test "a search-blacklisted author is withheld from search results" do
    @limited.update!(search_blacklist: true)
    Tweet.create!(user: @limited, body: "find me in search please")

    get explore_path(q: "search please")
    assert_response :success
    assert_no_match(/find me in search please/, response.body,
                    "a search-blacklisted author must not appear in search")
  end

  test "a search blacklist does not delete the post or hide it from the author" do
    @limited.update!(search_blacklist: true)
    post = Tweet.create!(user: @limited, body: "still on my profile timeline")

    delete logout_path
    sign_in @limited
    get home_path
    assert_response :success
    assert_match "still on my profile timeline", response.body,
                 "the flag limits discovery, it does not hide the post from its author"
    assert Tweet.visible.exists?(id: post.id)
  end

  test "a search-blacklisted author is left out of the people search" do
    @limited.update!(search_blacklist: true, display_name: "Findable Person")

    get explore_path(q: "Findable", tab: "people")
    assert_response :success
    assert_no_match(%r{/u/reach_limited}, response.body,
                    "the account itself should not be surfaced by search either")
  end

  test "a trend-blacklisted author does not count toward a trend" do
    # Two ordinary authors must fall just short of the three-author threshold
    # once the blacklisted chatter is discounted, so the tag never trends.
    @limited.update!(trends_blacklist: true)
    a = create_user(username: "reach_tr_a")
    b = create_user(username: "reach_tr_b")
    [ a, b ].each { |u| Tweet.create!(user: u, body: "talking about #reachlimited") }
    Tweet.create!(user: @limited, body: "also talking about #reachlimited")

    assert_empty Tweet.top_trends.map(&:first).grep("reachlimited"),
                 "a trend-blacklisted author's tag must not reach the trend list"
  end

  test "a trend blacklist only limits trends, not the author's own posts" do
    @limited.update!(trends_blacklist: true)
    Tweet.create!(user: @limited, body: "ordinary post, no tag scrutiny")

    get home_path
    assert_response :success
    assert_match "ordinary post, no tag scrutiny", response.body
  end

  test "do-not-amplify keeps the author out of other readers' timelines" do
    @limited.update!(do_not_amplify: true)
    Tweet.create!(user: @limited, body: "do not amplify this body")

    get home_path
    assert_response :success
    assert_no_match(/do not amplify this body/, response.body,
                    "another reader's timeline must not carry an amplified post")
  end

  test "do-not-amplify still shows the author their own posts" do
    @limited.update!(do_not_amplify: true)
    Tweet.create!(user: @limited, body: "my own post, still mine")

    delete logout_path
    sign_in @limited
    get home_path
    assert_response :success
    assert_match "my own post, still mine", response.body,
                 "the flag cuts other people's reach, not the author's own view"
  end

  test "do-not-amplify suppresses a retweet of the limited author" do
    @limited.update!(do_not_amplify: true)
    original = Tweet.create!(user: @limited, body: "the suppressed original")
    booster = create_user(username: "reach_booster")
    Follow.create!(follower: @me, followee: booster)
    Tweet.create!(user: booster, body: "boost", retweet_of_id: original.id)

    get home_path
    assert_response :success
    assert_no_match(/the suppressed original/, response.body,
                    "a retweet is somebody else lending reach, so it is suppressed too")
  end

  test "clearing a reach limit restores the account's reach" do
    @limited.update!(do_not_amplify: true)
    Tweet.create!(user: @limited, body: "reach comes and goes")
    @limited.update!(do_not_amplify: false)

    get home_path
    assert_response :success
    assert_match "reach comes and goes", response.body,
                 "a cleared flag must not leave the post withheld"
  end
end
