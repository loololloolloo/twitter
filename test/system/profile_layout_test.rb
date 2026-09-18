require "application_system_test_case"

# The profile page was reported as: the picture's box sits off to one side of
# the banner rather than in it, and at narrower widths the box overlaps the
# content below. Both are geometry claims, so they are measured here in a real
# browser instead of being eyeballed.
#
# The 2019 profile draws the picture straddling the banner's bottom edge on
# purpose: half the circle is over the banner and half over the details below it.
# That is measured as well, along with the requirement that the frame never
# leaves the profile card and never collides with the text beside it.
class ProfileLayoutTest < ApplicationSystemTestCase
  # Wide enough for the full three-column layout, then the two widths below it
  # where the old rules let the picture drift.
  WIDTHS = [ 1400, 980, 800 ].freeze

  setup do
    @user = create_profile(avatar: true, banner: true)
    sign_in_as(@user)
  end

  WIDTHS.each do |width|
    test "the picture straddles the banner's bottom edge at #{width}px" do
      visit_profile(width)

      banner = box(".profile-canopy")
      frame = box(".statbar-avatar-frame")

      # Left-aligned and narrower than the banner, so it is anchored to the
      # banner rather than floating beside it.
      assert_operator frame[:left], :>=, banner[:left], "picture starts left of the banner"
      assert_operator frame[:right], :<=, banner[:right] + 0.5,
                      "picture runs past the banner's right edge"
      assert_operator frame[:top], :>=, banner[:top],
                      "picture starts above the banner's top edge"

      # The deliberate straddle: the frame crosses the banner's bottom edge, and
      # it crosses it by about half its own height, so the circle's centre sits
      # on the line between the banner and the card below it.
      assert_operator frame[:bottom], :>, banner[:bottom],
                      "picture should straddle the banner's bottom edge"
      below = frame[:bottom] - banner[:bottom]
      assert_in_delta below, frame[:height] / 2.0, frame[:height] / 4.0,
                      "the picture should be about half below the banner's edge"
    end

    test "the picture never leaves the profile card at #{width}px" do
      visit_profile(width)

      card = box(".profile-header")
      frame = box(".statbar-avatar-frame")

      assert_operator frame[:top], :>=, card[:top], "picture starts above the card"
      assert_operator frame[:bottom], :<=, card[:bottom] + 0.5,
                      "picture hangs out of the bottom of the card"
    end

    test "the picture stays clear of the name and actions at #{width}px" do
      visit_profile(width)

      frame = box(".statbar-avatar-frame")

      # The details block starts at the banner's bottom edge and the picture
      # overlaps into it by design, so the block as a whole is not the thing to
      # measure against; the text and buttons beside the picture are.
      name = box(".profile-details-name")
      refute overlapping?(frame, name), "picture overlaps the name: #{frame} vs #{name}"

      actions = box(".profile-actions")
      refute overlapping?(frame, actions), "picture overlaps the actions: #{frame} vs #{actions}"
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

    # The bannerless band is shorter, but it still has to hold the picture's top
    # edge, and the picture still straddles its bottom edge.
    assert_operator frame[:top], :>=, banner[:top],
                    "picture starts above the bannerless band"
    assert_operator frame[:bottom], :>, banner[:bottom],
                    "picture should straddle the bannerless band's bottom edge"
    refute overlapping?(frame, box(".profile-details-name"))
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