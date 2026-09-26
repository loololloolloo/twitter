require "application_system_test_case"

# Revealing queued entries on the home timeline has to clear the empty-state
# block that stands in for the stream. That block was moved onto the shared
# empty-state shape and the reveal handler was left removing the old `.empty`
# row, so a viewer who arrived at an empty timeline and revealed a new entry saw
# "Your Home timeline is empty" sitting above it. The handler and the markup live
# in different files, so the drift is only visible in a browser: the poll and the
# reveal click run here against the app's own rendered row.
class TimelineEmptyStateTest < ApplicationSystemTestCase
  # The poll runs every five seconds, so the queued entry is waited for rather
  # than assumed to be there on the first tick.
  POLL_WAIT = 15

  setup do
    @user = create_member
    sign_in_as(@user)
  end

  test "revealing a new entry clears the empty-state block" do
    visit "/home?show=latest"
    assert_selector ".timeline .empty-state", wait: 5

    # An entry posted after the page was drawn is what the open timeline queues.
    # It belongs to the viewer, so the home feed carries it without a follow.
    Tweet.create!(user: @user, body: "An entry that arrived while the page was open")
    reveal_queued_entry

    assert_selector ".timeline [data-tweet]", wait: 5
    assert_no_selector ".timeline .empty-state"
  end

  test "the timeline is left holding only the revealed entry" do
    visit "/home?show=latest"
    assert_selector ".timeline .empty-state", wait: 5

    Tweet.create!(user: @user, body: "A second entry for the reveal")
    reveal_queued_entry
    assert_selector ".timeline [data-tweet]", wait: 5

    # The empty-state row is removed, not merely hidden: a leftover row would
    # still take space above the entry.
    rows = page.evaluate_script(
      "Array.from(document.querySelectorAll('.timeline > li')).map(function (li) { " \
      "return li.querySelector('[data-tweet]') ? 'tweet' : li.className; })"
    )
    assert_equal [ "tweet" ], rows,
                 "the timeline should hold only the revealed entry"
  end

  private

  # The bar is unhidden by the poll once it has queued something, so waiting for
  # it is how the test knows the entry is pending before the reveal is clicked.
  def reveal_queued_entry
    assert_selector "#new-tweets:not([hidden])", wait: POLL_WAIT
    find("#new-tweets-link").click
  end

  def sign_in_as(user)
    visit "/login"
    fill_in "identifier", with: user.username
    fill_in "password", with: "password123"
    click_button "Log in"
    assert_selector ".timeline, .compose", wait: 5
  end

  def create_member
    User.create!(
      username: "empty_stream",
      display_name: "Empty Stream Member",
      email: "empty_stream@example.com",
      password_hash: PasswordDigest.hash("password123"),
      role: Role.find_by!(name: "user")
    )
  end
end
