require "application_system_test_case"

# "Gaps in the navbars" is a geometry claim, so it is measured in a real browser
# rather than eyeballed. The default browser zoom is 100%, which is the case the
# complaint is about: the same window at 110% looked right because the CSS
# viewport was narrower. These widths therefore bracket a wide desktop at 100%
# and the narrower effective viewport that 110% produces.
class ShellLayoutTest < ApplicationSystemTestCase
  WIDTHS = [ 1920, 1745, 1440, 1280 ].freeze

  setup do
    @user = create_member
    sign_in_as(@user)
  end

  WIDTHS.each do |width|
    test "the sidebar meets the content band without a void at #{width}px" do
      visit_home(width)

      rail = box(".side-nav")
      main = box(".app-main")

      # The only space between the two should be the gutter the grid declares,
      # not a growing void. A centred content band inside the leftover room is
      # what produced the gap: the wider the window, the bigger it got.
      gutter = main[:left] - rail[:right]
      assert_operator gutter, :<=, 32,
                      "a #{gutter.round}px void sits between the sidebar and the content"
    end

    test "the content band is flush with the window at #{width}px" do
      visit_home(width)

      main = box(".app-main")
      body_right = page.evaluate_script("document.documentElement.clientWidth")

      # The band carries the stream and the right rail. Once the sidebar is
      # pinned left, the band has to run to the window's right edge; stopping
      # short leaves a gap beside the rail.
      assert_operator body_right - main[:right], :<=, 1,
                      "the content band stops #{body_right - main[:right]}px short of the edge"
    end

    test "the sidebar's own rows do not drift apart at #{width}px" do
      visit_home(width)

      # The rail's controls are a stack of rows. If the stack is spaced with a
      # stretchy gap, the rows spread as the rail grows taller, which reads as
      # gaps inside the sidebar itself.
      compose = box(".side-compose")
      account = box(".side-account")

      assert_operator account[:top] - compose[:bottom], :<=, 40,
                      "the account block floats #{account[:top] - compose[:bottom]}px below the rail"
    end

    test "the page does not scroll sideways at #{width}px" do
      visit_home(width)
      assert_operator horizontal_overflow, :<=, 0
    end
  end

  test "the admin bar's links do not wrap into a ragged row at 100% zoom" do
    admin = create_admin
    sign_in_as(admin)
    page.driver.browser.manage.window.resize_to(1920, 1000)
    visit "/admin"
    assert_selector ".topnav", wait: 5

    links = page.evaluate_script(<<~JS)
      (function () {
        var nodes = document.querySelectorAll(".topnav a");
        var tops = [];
        for (var i = 0; i < nodes.length; i++) {
          tops.push(Math.round(nodes[i].getBoundingClientRect().top));
        }
        return tops;
      })()
    JS

    # Wrapping the bar onto a second line is what leaves the ragged holes the
    # complaint describes; a single row keeps the links evenly spaced.
    assert_equal 1, links.uniq.size,
                 "the admin bar wrapped onto #{links.uniq.size} rows: #{links.uniq.inspect}"
  end

  # At phone widths the 2019 client carried no left rail: the four primaries
  # moved into a bar on the bottom edge. Measuring it catches the two ways the
  # shape can be wrong - the bar rendering off-screen, or the rail keeping its
  # column and squeezing the stream instead of being dropped.
  test "the phone bar replaces the rail at a phone width" do
    page.driver.browser.manage.window.resize_to(390, 844)
    visit "/home"
    assert_selector ".app-shell", wait: 5

    assert_equal "none", page.evaluate_script(
      "getComputedStyle(document.querySelector('.side-nav')).display"
    ),
                 "the rail kept its column at a phone width"

    bar = box(".mobile-nav")
    # A fixed bar is anchored to the layout viewport, so that - not
    # window.innerHeight, which also counts the scrollbar band - is what it has
    # to meet. Measuring the wrong box made a correctly-pinned bar look 15px low.
    bottom_gap, viewport_w = page.evaluate_script(<<~JS)
      (function () {
        var r = document.querySelector('.mobile-nav').getBoundingClientRect();
        return [
          Math.round(document.documentElement.clientHeight - r.bottom),
          document.documentElement.clientWidth
        ];
      })()
    JS
    assert_operator bottom_gap, :<=, 1,
                    "the bar hangs #{bottom_gap}px below the viewport"
    assert_operator bar[:width], :>=, viewport_w - 1,
                    "the bar spans only #{bar[:width]}px of the #{viewport_w}px viewport"

    # The floating compose control stands in for the rail's pill; it has to
    # clear the bar rather than sit underneath it.
    clearance = page.evaluate_script(<<~JS)
      (function () {
        var bar = document.querySelector('.mobile-nav').getBoundingClientRect();
        var compose = document.querySelector('.mobile-compose').getBoundingClientRect();
        return Math.round(bar.top - compose.bottom);
      })()
    JS
    assert_operator clearance, :>=, 0,
                    "the compose control overlaps the bottom bar by #{-clearance}px"
  end

  private

  def visit_home(width)
    page.driver.browser.manage.window.resize_to(width, 1000)
    visit "/home"
    assert_selector ".app-shell", wait: 5
  end

  def sign_in_as(user)
    visit "/login"
    fill_in "identifier", with: user.username
    fill_in "password", with: "password123"
    click_button "Log in"
    assert_selector ".timeline, .app-shell", wait: 5
  end

  def create_member
    User.create!(
      username: "shell_member",
      display_name: "Shell Member",
      email: "shell_member@example.com",
      password_hash: PasswordDigest.hash("password123"),
      role: Role.find_by!(name: "user")
    )
  end

  def create_admin
    User.create!(
      username: "shell_admin",
      display_name: "Shell Admin",
      email: "shell_admin@example.com",
      password_hash: PasswordDigest.hash("password123"),
      role: Role.find_by!(name: "admin")
    )
  end
end