require "application_system_test_case"

# The profile page was reported as: the picture's box sits off to one side of
# the banner rather than in it, and at narrower widths the box overlaps the
# stat bar and the sidebar. Both are geometry claims, so they are measured here
# in a real browser instead of being eyeballed.
class ProfileLayoutTest < ApplicationSystemTestCase
  # Wide enough for the full three-column layout, then the two widths below it
  # where the old rules let the picture drift.
  WIDTHS = [ 1400, 980, 800 ].freeze

  setup do
    @user = create_profile(avatar: true, banner: true)
    sign_in_as(@user)
  end

  WIDTHS.each do |width|
    test "the picture box sits inside the banner at #{width}px" do
      visit_profile(width)

      banner = box(".profile-canopy")
      frame = box(".statbar-avatar-frame")

      # Inside the banner on every edge, which is what "in the banner, not
      # offset from it" means.
      assert_operator frame[:left], :>=, banner[:left], "picture starts left of the banner"
      assert_operator frame[:right], :<=, banner[:right] + 0.5,
                      "picture runs past the banner's right edge"
      assert_operator frame[:top], :>=, banner[:top],
                      "picture starts above the banner's top edge"
      assert_operator frame[:bottom], :<=, banner[:bottom] + 0.5,
                      "picture hangs below the banner instead of sitting in it"
    end

    test "the picture box stays clear of the stat bar at #{width}px" do
      visit_profile(width)

      frame = box(".statbar-avatar-frame")
      bar = box(".profile-statbar")

      refute overlapping?(frame, bar), "picture box overlaps the stat bar: #{frame} vs #{bar}"
      assert_operator frame[:bottom], :<=, bar[:top] + 0.5
    end

    test "the picture box stays clear of the sidebar at #{width}px" do
      visit_profile(width)

      frame = box(".statbar-avatar-frame")
      side = box(".profile-side")

      refute overlapping?(frame, side), "picture box overlaps the sidebar: #{frame} vs #{side}"
    end

    test "the page does not scroll sideways at #{width}px" do
      visit_profile(width)

      assert_operator horizontal_overflow, :<=, 0,
                      "the page overflows the viewport horizontally by #{horizontal_overflow}px"
    end
  end

  test "a profile with no banner still holds the picture" do
    @user.update_columns(banner_path: nil)
    visit_profile(1400)

    banner = box(".profile-canopy")
    frame = box(".statbar-avatar-frame")

    assert_operator frame[:top], :>=, banner[:top]
    assert_operator frame[:bottom], :<=, banner[:bottom] + 0.5,
                    "picture hangs below the bannerless band"
    refute overlapping?(frame, box(".profile-statbar"))
  end

  test "the metrics row is not covered by the picture" do
    visit_profile(1400)

    frame = box(".statbar-avatar-frame")
    metrics = box(".statbar-metrics")

    refute overlapping?(frame, metrics), "picture box overlaps the metrics: #{frame} vs #{metrics}"
  end

  test "the picture sits near the banner's left edge" do
    visit_profile(1400)

    banner = box(".profile-canopy")
    frame = box(".statbar-avatar-frame")

    # The reference layout leaves a small margin, not a centred or right-aligned
    # picture.
    assert_in_delta frame[:left], banner[:left] + 15, 20
  end

  private

  def visit_profile(width)
    page.driver.browser.manage.window.resize_to(width, 1000)
    visit "/u/#{@user.username}"
    assert_selector ".profile-canopy", wait: 5
  end

  # The profile is behind the login, and a system test drives a separate browser
  # session, so the session has to be established through the login form.
  def sign_in_as(user)
    visit "/login"
    fill_in "identifier", with: user.username
    fill_in "password", with: "password123"
    click_button "Log in"
    assert_selector ".timeline, .profile-canopy", wait: 5
  end

  # A user with the two pictures the profile needs, built through the model
  # directly because the system test drives a separate browser session.
  def create_profile(avatar:, banner:)
    user = User.create!(
      username: "layout_member",
      display_name: "Layout Member",
      email: "layout_member@example.com",
      password_hash: PasswordDigest.hash("password123"),
      role: Role.find_by!(name: "user"),
      bio: "Testing the profile layout."
    )
    user.update_columns(avatar_path: avatar ? "layout-avatar.png" : nil,
                        banner_path: banner ? "layout-banner.png" : nil)
    write_placeholder("layout-avatar.png")
    write_placeholder("layout-banner.png")
    user
  end

  # The geometry being measured does not depend on the picture's contents, so a
  # small stand-in file is enough; it keeps the test from needing image
  # processing.
  def write_placeholder(name)
    uploads = Rails.root.join("public", "uploads")
    FileUtils.mkdir_p(uploads)
    path = uploads.join(name)
    return if File.exist?(path)

    # A 1x1 transparent PNG.
    png = [ "89504e470d0a1a0a0000000d494844520000000100000001080600000" \
            "01f15c4890000000a49444154789c6300010000050001" \
            "0d0a2db40000000049454e44ae426082" ].pack("H*")
    File.binwrite(path, png)
  end
end