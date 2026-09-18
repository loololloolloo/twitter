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
    # The sidebar is filled with live counts and shortcuts, not a second copy of
    # the top bar's section links.
    assert_includes response.body, 'class="rail-block"'
    assert_no_match(/class="admin-nav"/, response.body)
  end
end