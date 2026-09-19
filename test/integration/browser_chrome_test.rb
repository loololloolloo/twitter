require "test_helper"

# The browser tab is deliberately generic: every page, signed in or out, public
# or panel, presents the same title and favicon. A page that leaks its own name
# into the tab - a profile, the admin panel - breaks that, so the whole surface
# is swept rather than spot-checked.
class BrowserChromeTest < ActionDispatch::IntegrationTest
  TITLE = "<title>Clever | Login</title>".freeze
  FAVICON = "/clever-favicon-32.png".freeze

  test "signed-out pages all carry the neutral title and favicon" do
    # `/` redirects a signed-out visitor to the login page, so it is followed
    # rather than asserted on directly.
    [ login_path, signup_path, about_path, help_path, tos_path, privacy_path ].each do |path|
      get path
      assert_includes response.body, TITLE, "#{path} has the wrong title"
      assert_includes response.body, FAVICON, "#{path} has the wrong favicon"
    end

    get root_path
    follow_redirect!
    assert_includes response.body, TITLE, "the root redirect has the wrong title"
    assert_includes response.body, FAVICON, "the root redirect has the wrong favicon"
  end

  test "signed-in pages all carry the neutral title, including profiles" do
    me = create_user(username: "chrome_me", role: "owner")
    other = create_user(username: "chrome_other")
    tweet = Tweet.create!(user: other, body: "hello")

    sign_in(me)

    [ home_path, explore_path, notifications_path, messages_path, users_path,
      profile_path(me.username), profile_path(other.username), tweet_path(tweet),
      settings_path, bookmarks_path, about_path ].each do |path|
      get path
      assert_includes response.body, TITLE, "#{path} has the wrong title"
      refute_match(/<title>[^<]*chrome_me/, response.body,
                   "#{path} put the account name in the tab")
    end
  end

  test "the admin panel carries the neutral title too" do
    owner = create_user(username: "chrome_admin", role: "owner")
    sign_in(owner)

    [ admin_root_path, admin_users_path ].each do |path|
      get path
      assert_includes response.body, TITLE, "#{path} has the wrong title"
      refute_includes response.body, "<title>Admin", "#{path} leaked its own name"
    end
  end

  test "no view sets a page title of its own" do
    # The layout owns the title now. A leftover `content_for :title` in a view
    # would be dead weight, and would put the page's name in the tab again if
    # the layout ever yielded it.
    offenders = Rails.root.glob("app/views/**/*.erb").select do |file|
      file.read.include?("content_for :title")
    end

    assert_empty offenders.map { |f| f.relative_path_from(Rails.root).to_s },
                 "these views still set their own page title"
  end

  test "the favicon files are present and served" do
    # `/favicon.ico` is what a browser asks for when a page names no icon, so a
    # copy lives there too rather than letting the default request 404.
    %w[clever-favicon-32.png clever-favicon-192.png
       clever-favicon-180.png clever-favicon.png favicon.ico].each do |name|
      path = Rails.root.join("public", name)
      assert path.exist?, "missing public/#{name}"
      assert File.size(path).positive?, "public/#{name} is empty"
    end
  end
end
