require "test_helper"

# The 2019 empty state - a glyph over a heading and a line naming what would
# fill the screen - reached the primary streams first. These four surfaces kept
# the older bare sentence sitting in a list row, which reads as a row that
# failed to render rather than as a deliberate empty screen.
class ListAndPeopleEmptyStatesTest < ActionDispatch::IntegrationTest
  setup do
    @alice = create_user(username: "alice")
  end

  # ----------------------------------------------------- follow requests

  test "no pending follow requests shows the 2019 empty state" do
    sign_in @alice

    get follow_requests_path
    assert_response :success
    assert_match "No pending follow requests", response.body
    assert_select ".row-list .empty-state .empty-state-icon"
    assert_select ".row-list .empty-note", count: 0
  end

  test "the follow requests empty state gives way to a pending request" do
    bob = create_user(username: "bob")
    @alice.update!(protected: true)
    FollowRequest.create!(requester: bob, target: @alice)

    sign_in @alice
    get follow_requests_path
    assert_select ".row-list .empty-state", count: 0
    assert_match "@bob", response.body
  end

  # --------------------------------------------------------- who to follow

  test "a directory with no other accounts shows the 2019 empty state" do
    sign_in @alice

    get users_path
    assert_response :success
    assert_match "Nobody else has signed up yet", response.body
    assert_select ".row-list .empty-state .empty-state-icon"
    assert_select ".row-list .empty-note", count: 0
  end

  test "the directory empty state gives way to the account list" do
    create_user(username: "bob")
    sign_in @alice

    get users_path
    assert_select ".row-list .empty-state", count: 0
    assert_match "@bob", response.body
  end

  # ------------------------------------------------------------- lists

  test "a list with no member posts shows the 2019 empty state" do
    list = List.create!(user: @alice, name: "Quiet")

    sign_in @alice
    get list_path(list)
    assert_response :success
    assert_match "No Tweets in this List yet", response.body
    assert_select ".tweet-list .empty-state .empty-state-icon"
    assert_select ".tweet-list .empty-note", count: 0
  end

  test "the list timeline empty state gives way to a member's post" do
    bob = create_user(username: "bob")
    list = List.create!(user: @alice, name: "Reading")
    list.list_memberships.create!(user: bob)
    Tweet.create!(user: bob, body: "a post from the list")

    sign_in @alice
    get list_path(list)
    assert_select ".tweet-list .empty-state", count: 0
    assert_match "a post from the list", response.body
  end

  test "a list with no members shows the 2019 empty state on the manage screen" do
    list = List.create!(user: @alice, name: "Fresh")

    sign_in @alice
    get list_members_path(list)
    assert_response :success
    assert_match "This List has no members yet", response.body
    assert_select ".empty-state .empty-state-icon", minimum: 1
    assert_select ".empty-note", count: 0
  end

  test "the members empty state gives way to the member row" do
    bob = create_user(username: "bob")
    list = List.create!(user: @alice, name: "Reading")
    list.list_memberships.create!(user: bob)

    sign_in @alice
    get list_members_path(list)
    assert_match "@bob", response.body
    assert_no_match "This List has no members yet", response.body
  end

  test "a list already holding every account shows the no-suggestions empty state" do
    bob = create_user(username: "bob")
    list = List.create!(user: @alice, name: "Everyone")
    list.list_memberships.create!(user: bob)

    sign_in @alice
    get list_members_path(list)
    assert_response :success
    assert_match "No accounts left to suggest", response.body
  end
end
