require "test_helper"

# The profile is the 2015 three-column screen: a full-bleed banner, a stat bar
# whose metrics double as the tab navigation, and a body split into the
# account's details, its stream and a suggestion rail.
class ProfileLayoutTest < ActionDispatch::IntegrationTest
  setup do
    @me = create_user(username: "viewer_one", display_name: "Viewer One")
    @subject = create_user(
      username: "watched_one",
      display_name: "Watched Person",
      bio: "I post things",
      location: "London",
      website: "https://example.com/me"
    )
    sign_in(@me)
  end

  test "the profile renders the banner, stat bar and three columns" do
    get profile_path(@subject.username)

    assert_response :success
    assert_match(/profile-canopy/, response.body)
    assert_match(/profile-statbar/, response.body)
    assert_match(/profile-body/, response.body)
    assert_match(/profile-side/, response.body)
    assert_match(/profile-stream/, response.body)
    assert_match(/profile-aside/, response.body)
  end

  test "the stat bar carries the four metrics and links to their tabs" do
    get profile_path(@subject.username)

    %w[Tweets Following Followers Favorites].each do |label|
      assert_match(/#{label}/, response.body)
    end

    assert_match(%r{href="/u/watched_one/followers"}, response.body)
    assert_match(%r{href="/u/watched_one/following"}, response.body)
  end

  test "the stream tabs mark the current view active" do
    get profile_path(@subject.username)
    assert_match(/st-item is-active/, response.body)

    get profile_path(@subject.username, tab: "media")
    assert_match(/st-item is-active/, response.body)
    assert_match(/Media/, response.body)
  end

  test "the left column carries the account details" do
    get profile_path(@subject.username)

    assert_match(/I post things/, response.body)
    assert_match(/London/, response.body)
    assert_match(/example\.com/, response.body)
    assert_match(/Joined /, response.body)
  end

  test "the photo strip appears beside the details once the account has media" do
    get profile_path(@subject.username)
    assert_no_match(/photo-strip/, response.body)

    tweet = Tweet.create!(user: @subject, body: "look", media_path: "media/watched_one_1.png")
    assert tweet.media_path.present?

    get profile_path(@subject.username)
    assert_match(/photo-strip/, response.body)
  end

  test "the suggestion rail never suggests the profile being viewed" do
    create_user(username: "third_one", display_name: "Third Person")

    get profile_path(@subject.username)

    assert_match(/Who to follow/, response.body)
    assert_match(/@third_one/, response.body)
    assert_no_match(/@watched_one/, response.body.split("Who to follow").last.to_s)
  end

  test "the profile uses the wide page container" do
    get profile_path(@subject.username)
    assert_match(/page page-wide/, response.body)

    get home_path
    assert_no_match(/page page-wide/, response.body)
  end

  # The 2015 profile hung a 200px picture off the stat bar so it overlapped the
  # banner. It is the one element that defines the layout, so it is pinned here.
  test "the avatar is the 200px framed picture in the stat bar" do
    get profile_path(@subject.username)

    assert_match(/statbar-avatar-frame/, response.body)
    assert_match(/avatar avatar-200/, response.body)
  end

  # The bannerless backdrop has to be tall enough for the picture that rises
  # above the stat bar. It was 60px, so the frame's top rendered above the
  # backdrop and was clipped by the fixed top bar - on every profile, since no
  # account has a banner. The failure is in the stylesheet alone, with no markup
  # symptom, so the numbers that have to agree are checked here rather than
  # left to a browser measurement.
  test "the bannerless canopy is tall enough for the picture it backs" do
    css = Rails.root.join("app/assets/stylesheets/twitter.css").read

    rise = css[/^:root\s*\{[^}]*?--pfp-rise:\s*(\d+)px/m, 1].to_i
    headroom = css[/\.profile-canopy\.no-banner\s*\{\s*height:\s*calc\(var\(--pfp-rise\)\s*\+\s*(\d+)px\)/, 1].to_i
    frame = css[/\.statbar-avatar-frame\s*\{[^}]*?height:\s*(\d+)px/m, 1].to_i

    assert_operator rise, :>, 0, "the picture's rise above the bar has to be defined"
    assert_operator headroom, :>, 0,
                    "the backdrop needs headroom above the picture's top edge, not just the rise"
    assert_operator frame, :>, 0

    # The backdrop's height is the picture's rise plus its headroom. It has to
    # reach the picture's top, and it must not run past the picture's own height
    # or the tinted band would show below the frame.
    assert_operator rise + headroom, :<=, frame,
                    "the backdrop should not be taller than the picture it backs"
  end

  # The picture used to be pinned with `bottom` against `.statbar-avatar`. That
  # slot is a stretched flex item, so its height collapses once the bar wraps
  # its metrics onto a second row, and the picture slid down into the metrics at
  # narrow widths. It is pinned to the bar's top edge instead - the same line at
  # every width - so the offset below the banner never moves.
  test "the picture is pinned to the stat bar, not to the collapsing picture slot" do
    css = Rails.root.join("app/assets/stylesheets/twitter.css").read

    slot = css[/\.statbar-avatar\s*\{([^}]*)\}/m, 1]
    assert_no_match(/position:\s*relative/, slot,
                    "anchoring the frame to the picture slot reintroduces the drift")

    frame = css[/\.statbar-avatar-frame\s*\{([^}]*)\}/m, 1]
    assert_match(/position:\s*absolute/, frame)
    assert_match(/top:\s*calc\(-1\s*\*\s*var\(--pfp-rise\)\)/, frame)
    assert_no_match(/bottom:/, frame,
                    "a `bottom` offset is measured against the slot that collapses")

    # The scaled picture has to move with the same variable, or one of the two
    # rules drifts while the other stays put.
    tablet = media_blocks(css, "@media (max-width: 1000px)")
    assert_match(/top:\s*calc\(-1\s*\*\s*var\(--pfp-rise\)\)/, tablet)
  end

  # Pulls out every @media block with the given header. A balanced-brace scan is
  # needed because a block contains nested rules whose closing braces would
  # otherwise end a naive non-greedy match at the first inner rule. There is more
  # than one block per breakpoint in this stylesheet, so all are returned rather
  # than only the first.
  def media_blocks(css, header)
    blocks = []
    offset = 0

    while (start = css.index(header, offset))
      open = css.index("{", start)
      break if open.nil?

      depth = 0
      close = nil
      css[open..].each_char.with_index do |ch, i|
        depth += 1 if ch == "{"
        depth -= 1 if ch == "}"
        if depth.zero?
          close = open + i
          break
        end
      end
      break if close.nil?

      blocks << css[(open + 1), (close - open - 1)]
      offset = close + 1
    end

    blocks.join("\n")
  end

  # The stat bar is a 290px picture slot, a flexible metrics band and a 290px
  # action slot. With both outer slots fixed, anything narrower than the rail
  # layout pushed the action slot past the right edge and gave the whole page a
  # horizontal scrollbar. The bands have to be allowed to give up their widths.
  test "the stat bar bands shrink instead of overflowing a narrow viewport" do
    css = Rails.root.join("app/assets/stylesheets/twitter.css").read
    tablet = media_blocks(css, "@media (max-width: 1000px)")

    assert tablet.present?, "the stat bar needs a rule for viewports under 1000px"

    avatar = tablet[/\.statbar-avatar\s*\{[^}]*?width:\s*(\d+)px/m, 1].to_i
    assert_operator avatar, :>, 0
    assert_operator avatar, :<, 290, "the picture slot must shrink below its desktop width"

    actions = tablet[/\.statbar-actions\s*\{[^}]*?width:\s*(auto)/m, 1]
    assert_equal "auto", actions, "the action slot must not hold a fixed width when narrow"

    # The narrowed picture must not reintroduce the bug the desktop numbers
    # solve: it still has to fit entirely inside the bannerless backdrop.
    frame = tablet[/\.statbar-avatar-frame\s*\{[^}]*?height:\s*(\d+)px/m, 1].to_i
    tablet_rise = tablet[/--pfp-rise:\s*(\d+)px/m, 1].to_i
    headroom = css[/\.profile-canopy\.no-banner\s*\{\s*height:\s*calc\(var\(--pfp-rise\)\s*\+\s*(\d+)px\)/, 1].to_i

    assert_operator frame, :>, 0
    assert_operator tablet_rise, :>, 0,
                    "the scaled picture needs its own rise or it drifts out of the backdrop"
    assert_operator tablet_rise + headroom, :<=, frame,
                    "the scaled picture must still fit the bannerless backdrop"
  end

  # Below the rail breakpoint even the shrunk bands do not fit on one row, so
  # the metrics move to their own line and the bar grows to hold them.
  test "the metrics wrap onto their own row on a narrow viewport" do
    css = Rails.root.join("app/assets/stylesheets/twitter.css").read
    phone = media_blocks(css, "@media (max-width: 960px)")

    assert phone.present?, "the stat bar needs a wrapping rule for narrow viewports"
    assert_match(/\.statbar-inner\s*\{[^}]*flex-wrap:\s*wrap/, phone)
    assert_match(/\.statbar-metrics\s*\{[^}]*flex-basis:\s*100%/, phone)
    assert_match(/\.profile-statbar\s*\{[^}]*height:\s*auto/, phone)
  end

  # The three columns are two fixed 290px rails around a flexible stream, so
  # below the rail breakpoint they have to stack rather than push the page wide.
  test "the profile columns stack on a narrow viewport" do
    css = Rails.root.join("app/assets/stylesheets/twitter.css").read
    rail = media_blocks(css, "@media (max-width: 960px)")

    assert_match(/\.profile-body\s*\{[^}]*flex-direction:\s*column/, rail)
    assert_match(/\.profile-aside[^{]*\{[^}]*width:\s*100%/, rail)
    assert_match(/\.profile-stream[^{]*\{[^}]*width:\s*100%/, rail)
  end
end
