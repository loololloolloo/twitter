require "test_helper"

# 2019's Notifications screen, with nothing in it, was a centred bell glyph over
# a heading and a one-line explanation of what will fill the list - the same
# shape as the empty Bookmarks screen - rather than a bare sentence in a list
# row. Both tabs are empty lists over the same table, so both carry the state.
class NotificationsEmptyTest < ActionDispatch::IntegrationTest
  setup do
    @me = create_user(username: "clear_me")
    @actor = create_user(username: "clear_actor")
  end

  test "an empty notifications screen shows the 2019 empty state" do
    sign_in @me

    get notifications_path
    assert_response :success
    assert_match "empty-state", response.body
    assert_select ".empty-state .empty-state-icon"
    assert_match "Nothing to see here", response.body
  end

  test "the mentions tab carries the same empty state when it has no mentions" do
    sign_in @me
    Notification.create!(user: @me, actor: @actor, kind: "like")

    get notifications_path
    assert_no_match(/empty-state/, response.body, "the All tab has an item and should not be empty")

    get notifications_path(tab: "mentions")
    assert_response :success
    assert_match "empty-state", response.body, "the Mentions tab is empty but lost its empty state"
  end

  test "the empty state is the absence of notifications, so an item replaces it" do
    sign_in @me

    get notifications_path
    assert_match "empty-state", response.body

    Notification.create!(user: @me, actor: @actor, kind: "follow")
    get notifications_path
    assert_no_match(/empty-state/, response.body)
  end
end
