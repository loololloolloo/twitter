require "application_system_test_case"

# The timeline was reported as having a large gap between the author's name and
# the post body, where only a small one belongs. The gap is geometry, so it is
# measured in a real browser rather than eyeballed.
#
# The cause was the overflow menu: it is a flex item inside the header row, so
# as soon as the name, handle and timestamp filled that row the menu wrapped
# onto a line of its own. The button's 28px height then opened a second line
# above the body and pushed it down, which is what read as the gap. The menu is
# now pinned to the header's corner, so the header keeps to its text height and
# the body follows the name by the line spacing alone.
class TweetSpacingTest < ApplicationSystemTestCase
  WIDTHS = [ 1400, 1200, 1000 ].freeze

  setup do
    @user = User.create!(
      username: "spacing_member", display_name: "Spacing Member",
      email: "spacing_member@example.com",
      password_hash: PasswordDigest.hash("password123"),
      role: Role.find_by!(name: "user")
    )
    Tweet.create!(user: @user, body: "checking the spacing here")
  end

  # A short name keeps the header to one line at these widths, so any gap past
  # the line spacing is the menu's phantom line rather than legitimate wrapping.
  WIDTHS.each do |width|
    test "the body follows the name closely at #{width}px" do
      page.driver.browser.manage.window.resize_to(width, 1000)
      sign_in
      assert_selector ".tweet .tweet-text", wait: 5

      gap = page.evaluate_script(<<~JS)
        (function () {
          var name = document.querySelector(".tweet .tweet-name");
          var text = document.querySelector(".tweet .tweet-text");
          var nr = document.createRange(); nr.selectNodeContents(name);
          var tr = document.createRange(); tr.selectNodeContents(text);
          return tr.getBoundingClientRect().top - nr.getBoundingClientRect().bottom;
        })()
      JS

      assert gap < 20,
             "gap between name and body was #{gap}px at #{width}px; the header's " \
             "text alone accounts for about 5px"
      assert gap.positive?, "the body should not overlap the name"
    end
  end

  # The invariant the fix rests on: the menu is out of the header's flow, so it
  # contributes no height. Measured with a name long enough to fill the row,
  # which is when the menu used to wrap and open its extra line.
  test "the overflow menu adds no height to the header" do
    @user.update!(display_name: "Bartholomew Fitzgerald-Kensington III")
    sign_in
    assert_selector ".tweet-menu", wait: 5

    metrics = page.evaluate_script(<<~JS)
      (function () {
        var head = document.querySelector(".tweet .tweet-head");
        var menu = document.querySelector(".tweet .tweet-menu");
        var hb = head.getBoundingClientRect();
        var mb = menu.getBoundingClientRect();
        var withMenu = hb.height;
        menu.style.display = "none";
        var withoutMenu = head.getBoundingClientRect().height;
        menu.style.display = "";
        return {
          withMenu: withMenu,
          withoutMenu: withoutMenu,
          topOffset: mb.top - hb.top
        };
      })()
    JS

    assert_equal 0, metrics["topOffset"].round,
                 "the menu should be pinned to the top of the header"
    assert_equal metrics["withoutMenu"].round, metrics["withMenu"].round,
                 "the menu added #{metrics['withMenu'].round - metrics['withoutMenu'].round}px " \
                 "to the header, which opens a line above the body"
  end

  private

  def sign_in
    visit "/login"
    fill_in "identifier", with: @user.username
    fill_in "password", with: "password123"
    click_button "Log in"
  end
end