require "test_helper"

# 2019's Notifications screen split the list into "All" and "Mentions" with the
# same tab strip every other stream uses: the active cell bold with a blue
# underline, the other grey. That styling lives entirely on `.pt-item`, so a
# cell that drops the class silently falls back to the plain link styling and
# the strip stops reading as tabs - which is what the All / Mentions row did.
class NotificationsTabsTest < ActionDispatch::IntegrationTest
  setup do
    @me = create_user(username: "tab_me")
    @actor = create_user(username: "tab_actor")
    sign_in @me
  end

  test "the notifications tab strip styles its cells as tabs" do
    get notifications_path
    assert_response :success

    strip = response.body[%r{<ul class="profile-tabs">(.*?)</ul>}m, 1]
    assert_not_nil strip, "the notifications screen lost its All / Mentions strip"
    assert_equal 2, strip.scan(/class="pt-item/).size,
                 "each tab cell must carry pt-item or the tab CSS never applies"
  end

  test "the selected tab is marked active and the other links to its tab" do
    get notifications_path
    assert_response :success
    assert_select "ul.profile-tabs li.pt-item.is-active span", text: "All"
    assert_select "ul.profile-tabs li.pt-item a[href=?]", notifications_path(tab: "mentions"), text: "Mentions"

    get notifications_path(tab: "mentions")
    assert_response :success
    assert_select "ul.profile-tabs li.pt-item.is-active span", text: "Mentions"
    assert_select "ul.profile-tabs li.pt-item a[href=?]", notifications_path, text: "All"
  end
end
