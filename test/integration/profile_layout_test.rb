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

  test "the profile renders the 2019 header, banner, details and columns" do
    get profile_path(@subject.username)

    assert_response :success
    assert_match(/profile-canopy/, response.body)
    assert_match(/profile-header/, response.body)
    assert_match(/profile-details/, response.body)
    assert_match(/statbar-avatar-frame/, response.body)
    assert_match(/profile-tabs/, response.body)
    assert_match(/profile-aside/, response.body)
  end

  # The 2019 profile header kept Following and Followers under the bio and
  # dropped the Likes total the earlier client showed there. Likes survives only
  # as a tab, so it is asserted separately rather than as a header figure.
  test "the header carries the follow counts and links to their lists" do
    get profile_path(@subject.username)

    counts = response.body[/<p class="profile-follow-counts">.*?<\/p>/m].to_s
    assert_match(/Following/, counts)
    assert_match(/Followers/, counts)
    assert_no_match(/Likes/, counts)

    assert_match(%r{href="/u/watched_one/followers"}, response.body)
    assert_match(%r{href="/u/watched_one/following"}, response.body)
  end

  test "the 2019 tab strip offers tweets, replies, media and likes" do
    get profile_path(@subject.username)

    %w[Tweets].each { |label| assert_match(/#{label}/, response.body) }
    assert_match(/Tweets &amp; replies/, response.body)
    assert_match(/tab=replies/, response.body)
    assert_match(/tab=media/, response.body)
    assert_match(/tab=likes/, response.body)
  end

  test "the default tweets tab hides replies unless they are asked for" do
    root = Tweet.create!(user: @subject, body: "a root post")
    reply = Tweet.create!(user: @subject, body: "a reply", parent: root)

    get profile_path(@subject.username)
    assert_match(/a root post/, response.body)
    refute_match(/#{Regexp.escape(reply.body)}/, response.body)

    get profile_path(@subject.username, tab: "replies")
    assert_match(/a root post/, response.body)
    assert_match(/a reply/, response.body)
  end

  test "the stream tabs mark the current view active" do
    get profile_path(@subject.username)
    assert_match(/pt-item is-active/, response.body)

    get profile_path(@subject.username, tab: "media")
    assert_match(/pt-item is-active/, response.body)
    assert_match(/Media/, response.body)
  end

  test "the left column carries the account details" do
    get profile_path(@subject.username)

    assert_match(/I post things/, response.body)
    assert_match(/London/, response.body)
    assert_match(/example\.com/, response.body)
    assert_match(/Joined /, response.body)
  end

  test "the media tab shows the account's photos" do
    get profile_path(@subject.username, tab: "media")
    assert_no_match(/media-rail/, response.body)

    tweet = Tweet.create!(user: @subject, body: "look", media_path: "media/watched_one_1.png")
    assert tweet.media_path.present?

    get profile_path(@subject.username, tab: "media")
    assert_match(/media-rail/, response.body)
  end

  test "the suggestion rail never suggests the profile being viewed" do
    create_user(username: "third_one", display_name: "Third Person")

    get profile_path(@subject.username)

    assert_match(/Who to follow/, response.body)
    assert_match(/@third_one/, response.body)
    assert_no_match(/@watched_one/, response.body.split("Who to follow").last.to_s)
  end

  # The header no longer prints a Likes total, but the model still has to count
  # the reactions other people left on the account's posts rather than the ones
  # the account gave, which is what any other surface would report.
  test "the profile reports the likes its posts received, not the likes it gave" do
    mine = Tweet.create!(user: @subject, body: "my post", bonus_likes: 3)
    other = Tweet.create!(user: @me, body: "someone else's post")

    # Reactions other people put on the subject's posts are counted.
    Like.create!(user: @me, tweet: mine, kind: "like")
    Like.create!(user: @me, tweet: mine, kind: "favourite")
    # A reaction the subject gave to someone else's post is not.
    Like.create!(user: @subject, tweet: other, kind: "like")

    assert_equal 5, @subject.likes_received_count
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
  # The bannerless backdrop has to hold the upper half of the picture, which is
  # the part that sits over it. It was a 60px strip, so the frame rendered above
  # the backdrop and was clipped by the fixed top bar - on every profile, since
  # no account has a banner. The failure is in the stylesheet alone, with no
  # markup symptom, so the numbers that have to agree are checked here rather
  # than left to a browser measurement.
  test "the bannerless canopy is tall enough for the picture it holds" do
    css = Rails.root.join("app/assets/stylesheets/twitter.css").read

    overlap = css[/^:root\s*\{[^}]*?--pfp-overlap:\s*(\d+)px/m, 1].to_i
    headroom = css[/\.profile-canopy\.no-banner\s*\{[^}]*?height:\s*calc\([^;]*\+\s*(\d+)px\)/m, 1].to_i

    assert_operator overlap, :>, 0, "the picture's overlap of the banner's edge has to be defined"
    assert_operator headroom, :>, 0,
                    "the backdrop needs headroom above the picture's top edge"

    # The picture straddles the banner's bottom edge, so the band is the half of
    # the frame over it plus the headroom above it. The headroom should stay
    # modest rather than the band ballooning, since the rest of the circle sits
    # over the details block below.
    assert_operator headroom, :<, overlap,
                    "the headroom should not dwarf the half of the picture it holds"
  end

  # The picture slot is fixed so the picture keeps its circle; the details block
  # beside it is the part that gives up width, otherwise the page would scroll
  # sideways at narrow widths.
  test "the picture stays fixed while the details give up their width" do
    css = Rails.root.join("app/assets/stylesheets/twitter.css").read

    assert_match(/\.statbar-avatar\s*\{[^}]*flex-shrink:\s*0/, css,
                 "the picture slot must not be squeezed")

    # The narrowed picture still has to fit inside the bannerless band: the band
    # is sized from the picture's own variables, so both have to be scaled
    # together at this breakpoint or the picture outgrows what holds it.
    tablet = media_blocks(css, "@media (max-width: 1000px)")
    assert tablet.present?, "the profile needs a rule for viewports under 1000px"
    assert_match(/--pfp-size:\s*\d+px/, tablet,
                 "the picture has to scale with the narrow layout")
    assert_match(/--pfp-overlap:\s*\d+px/, tablet)
  end

  # Below the phone breakpoint the actions no longer fit beside the picture's
  # column, so they are allowed to wrap rather than being clipped.
  test "the profile actions reflow on a narrow viewport" do
    css = Rails.root.join("app/assets/stylesheets/twitter.css").read
    phone = media_blocks(css, "@media (max-width: 700px)")

    assert phone.present?, "the profile needs a wrapping rule for narrow viewports"
    assert_match(/\.profile-actions\s*\{[^}]*flex-wrap:\s*wrap/, phone)
  end

  # The stream sits in the flexible centre column with the rail beside it, so
  # below the rail breakpoint the rail has to stack rather than push the page
  # wider than the viewport.
  test "the profile columns stack on a narrow viewport" do
    css = Rails.root.join("app/assets/stylesheets/twitter.css").read
    rail = media_blocks(css, "@media (max-width: 960px)")

    assert_match(/\.profile-aside[^{]*\{[^}]*width:\s*100%/, rail)
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
end
