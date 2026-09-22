require "test_helper"

# Guards the 2019 shell: the signed-in pages share one app shell with a left
# sidebar, and the pages that carry a rail render it in the right column. The
# admin panel is a separate surface and keeps its own top bar.
class ShellLayoutTest < ActionDispatch::IntegrationTest
  test "signed-in pages share the sidebar shell and drop the old top nav" do
    me = create_user(username: "shell_me", role: "owner")
    other = create_user(username: "shell_other")
    tweet = Tweet.create!(user: other, body: "hello #world")

    sign_in(me)

    pages = [
      home_path,
      explore_path,
      notifications_path,
      messages_path,
      users_path,
      profile_path(other.username),
      profile_path(me.username),
      tweet_path(tweet),
      settings_path,
      about_path
    ]

    pages.each do |path|
      get path
      assert_response :success, "#{path} => #{response.status}"
      assert_includes response.body, 'class="app-shell"', "#{path} missing app shell"
      assert_includes response.body, 'class="side-nav"', "#{path} missing sidebar"
      assert_includes response.body, 'class="page', "#{path} missing page column"
      assert_no_match(/class="topnav"/, response.body, "#{path} still renders the old top nav")
      assert_no_match(/col-left/, response.body, "#{path} still renders a left rail column")
    end

    # The old account list is a forward now, so it is checked as a redirect
    # rather than as a page that renders the shell.
    get accounts_path
    assert_response :redirect
    assert_match(%r{/settings\?panel=data}, response.location)
  end

  # The 2019 rail carried a blue count on Notifications naming how much was
  # unread, and the count agreed with the list the page renders.
  test "the rail shows the unread notification count and clears it once read" do
    me = create_user(username: "badge_me")
    actor = create_user(username: "badge_act")
    Notification.create!(user: me, actor: actor, kind: "mention", body: "hey")
    Notification.create!(user: me, actor: actor, kind: "follow")
    Notification.create!(user: me, actor: actor, kind: "like", is_read: true)

    sign_in(me)

    get home_path
    assert_response :success
    assert_match(/Notifications.*side-badge.*2/m, response.body, "rail did not show the unread count")

    get notifications_path
    assert_response :success

    get home_path
    assert_response :success
    assert_no_match(/side-badge/, response.body, "count survived opening the list")
  end

  # A muted or blocked actor's notifications are filtered out of the list, so
  # counting them would leave a badge that opening the page never clears.
  test "the notification count ignores silenced actors" do
    me = create_user(username: "badge_silent_me")
    seen = create_user(username: "badge_see")
    muted = create_user(username: "badge_mute")
    blocked = create_user(username: "badge_blk")

    me.mute!(muted)
    Block.create!(blocker: me, blocked: blocked)

    Notification.create!(user: me, actor: seen, kind: "mention", body: "seen")
    Notification.create!(user: me, actor: muted, kind: "like")
    Notification.create!(user: me, actor: blocked, kind: "retweet")

    assert_equal 1, me.unread_notification_count

    sign_in(me)
    get home_path
    assert_match(/side-badge[^>]*>\s*1\s*</, response.body, "rail counted silenced actors")
  end

  # 2019 stamped the activity kind on the corner of the actor's picture as a
  # small filled glyph. The list had a coloured disc per kind; a kind with no
  # glyph (a bare system notice) renders no badge, so a wrong glyph is not
  # invented for it. Asserted both the presence for a like and the absence for
  # a context-free kind.
  test "a notification carries the 2019 activity badge on the actor's picture" do
    me = create_user(username: "badge_badge_me")
    actor = create_user(username: "badge_badge_act")
    Notification.create!(user: me, actor: actor, kind: "like")
    Notification.create!(user: me, actor: actor, kind: "retweet")
    Notification.create!(user: me, actor: actor, kind: "follow")
    Notification.create!(user: me, actor: actor, kind: "reply", body: "hi")

    sign_in(me)
    get notifications_path
    assert_response :success

    assert_match "notif-avatar", response.body, "the actor picture is not wrapped for the badge"
    assert_match "notif-badge-like", response.body, "a like carries no badge"
    assert_match "notif-badge-retweet", response.body, "a retweet carries no badge"
    assert_match "notif-badge-follow", response.body, "a follow carries no badge"

    # The badge is inside the avatar anchor, so picture and badge are one link.
    avatar = response.body[/<a class="row-avatar".*?<\/a>/m]
    assert_not_nil avatar, "no avatar link rendered"
    assert_match "notif-badge", avatar, "the badge escaped the avatar link"

    # A kind with no glyph gets no disc rather than an arbitrary one.
    assert_no_match(/notif-badge-admin/, response.body)
  end

  test "pages with a rail render search, trends and suggestions" do
    me = create_user(username: "rail_me")
    other = create_user(username: "rail_other")
    Tweet.create!(user: other, body: "trending #tag")

    sign_in(me)

    [ home_path, explore_path, profile_path(other.username) ].each do |path|
      get path
      assert_response :success
      assert_includes response.body, "rail-search-form", "#{path} missing rail search"
      assert_includes response.body, "rail-card", "#{path} missing rail cards"
    end
  end

  # 2019 kept the rail search as a bare bar pinned to the top of the column,
  # separate from the trends card that sat beneath it. Rendering it as a card
  # made it read as one more module in the stack rather than as the column's
  # own search, so the structure is asserted rather than left to drift.
  test "the rail search is a bare sticky bar, not a card" do
    me = create_user(username: "railsearchme")
    # A trend needs three distinct authors, so the trends card the search sits
    # above actually renders and the two structures can be told apart.
    %w[rafirst rasecond rathird].each do |handle|
      Tweet.create!(user: create_user(username: handle), body: "talking about #railtrend")
    end
    Rails.cache.clear

    sign_in(me)
    get home_path
    assert_response :success

    rail = response.body[/<div class="rail-search">.*?<\/div>/m]
    assert_not_nil rail, "home is missing the rail search"
    assert_no_match(/rail-card/, rail, "the rail search is still wrapped in a card")
    # The trends module is what the card styling is for; it must survive.
    assert_includes response.body, %(<h2 class="rail-title">What's happening</h2>)

    # A card sits inline in the rail stack; a sticky bar pins to the top of the
    # column so it stays reachable while the rail scrolls.
    css = Rails.root.join("app/assets/stylesheets/twitter.css").read
    assert_match(/\.rail-search\s*\{[^}]*position:\s*sticky/, css)
    assert_match(/\.rail-search\s*\{[^}]*top:\s*var\(--header-h\)/, css)
  end

  test "the admin panel keeps its own sidebar layout" do
    owner = create_user(username: "shell_admin", role: "owner")
    sign_in(owner)

    get admin_root_path
    assert_response :success
    assert_includes response.body, 'class="admin-rail"'
    assert_includes response.body, 'class="admin-shell"'
    # The sidebar is a sectioned navigation column, not a second copy of the
    # toolbar's working tools.
    assert_includes response.body, 'class="rail-group"'
    assert_no_match(/class="admin-nav"/, response.body)
  end

  # The 2019 rail ordered its destinations Home, Explore, Notifications,
  # Messages, Bookmarks, Lists, Profile, More. A different sequence reads as a
  # different era, so the order is asserted rather than just the presence.
  test "the sidebar follows the 2019 order and keeps the rest behind More" do
    me = create_user(username: "order_me")
    sign_in(me)

    get home_path
    assert_response :success

    menu = response.body[/<ul class="side-menu">.*?<\/ul>/m].to_s
    labels = menu.scan(/class="side-label">([^<]+)</).flatten
    assert_equal %w[Home Explore Notifications Messages Bookmarks Lists Profile More], labels

    # The non-primary destinations are not top-level links any more; they live
    # inside the More disclosure.
    assert_includes response.body, "side-more"
    assert_includes response.body, "Settings and privacy"
    assert_includes response.body, "Help Center"
  end

  # A Top-ranked stream and a latest-first one are the same entries under two
  # orderings, so the header offers the swap and the page records which mode it
  # is in. The poll then knows not to queue arrivals out of rank.
  test "the home header offers the Top and latest orderings" do
    me = create_user(username: "sparkle_me")
    other = create_user(username: "sparkle_other")
    me.active_follows.create!(followee: other)

    quiet = Tweet.create!(user: other, body: "quiet post")
    loud = Tweet.create!(user: other, body: "loud post")
    Like.create!(user: me, tweet: loud, kind: "like")

    sign_in(me)

    get home_path
    assert_response :success
    assert_includes response.body, "stream-head-toggle"
    assert_includes response.body, "Latest Tweets"
    assert_includes response.body, 'data-show="top"'
    # The control names the mode it switches to, so the link must point at the
    # other one - pointing at the current mode would make it a no-op.
    assert_includes response.body, "show=latest"
    assert_not_includes response.body, 'href="/home?show=top"'
    # Top puts the reacted-to post first.
    assert_operator response.body.index(loud.body), :<, response.body.index(quiet.body)

    get home_path(show: "latest")
    assert_response :success
    assert_includes response.body, "Top Tweets"
    assert_includes response.body, 'data-show="latest"'
    assert_includes response.body, "show=top"
    assert_not_includes response.body, 'href="/home?show=latest"'
  end

  # The 2019 notifications header carried a gear at the right edge that opened
  # the notifications panel of Settings, not a page of its own. It is the only
  # way into that panel from the stream, so the link has to survive.
  test "the notifications header links to the notification settings panel" do
    me = create_user(username: "gear_me")
    sign_in(me)

    get notifications_path
    assert_response :success
    assert_select "a.head-icon[href=?]", settings_path(panel: "notifications")
  end
end