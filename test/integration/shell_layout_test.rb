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
end