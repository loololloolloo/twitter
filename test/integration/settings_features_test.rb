require "test_helper"

# Settings holds three member-only tools: the light/dark appearance choice, the
# list of accounts this browser can switch between, and the delete-my-messages
# action. None of them are administrative.
class SettingsFeaturesTest < ActionDispatch::IntegrationTest
  setup do
    @me = create_user(username: "settings_one", display_name: "Settings One")
    sign_in(@me)
  end

  # ------------------------------------------------------------- appearance

  test "the light and dark choices are both offered" do
    get settings_path

    assert_response :success
    assert_match(/Appearance/, response.body)
    assert_match(/Light mode/, response.body)
    assert_match(/Dark mode/, response.body)
  end

  test "the root element carries the light theme by default" do
    get home_path

    assert_match(/data-theme="light"/, response.body)
  end

  test "choosing dark saves it to the account and renders the dark theme" do
    patch theme_path, params: { theme: "dark" }
    assert_response :redirect

    assert_equal "dark", @me.reload.theme

    get home_path
    assert_match(/data-theme="dark"/, response.body)
  end

  test "choosing a theme survives into the next request and back to light" do
    patch theme_path, params: { theme: "dark" }
    get settings_path
    assert_match(/data-theme="dark"/, response.body)

    patch theme_path, params: { theme: "light" }
    assert_equal "light", @me.reload.theme

    get settings_path
    assert_match(/data-theme="light"/, response.body)
  end

  test "an unknown theme value falls back to light rather than being stored" do
    patch theme_path, params: { theme: "chartreuse" }

    assert_equal "light", @me.reload.theme
  end

  test "a theme value cannot inject markup into the root element" do
    @me.update_column(:theme, %("><script>alert(1)</script>))

    get home_path

    refute_match(/<script>alert\(1\)<\/script>/, response.body)
    assert_match(/data-theme="light"/, response.body)
  end

  test "the theme is per account, not shared" do
    other = create_user(username: "other_theme")
    other.update!(theme: "dark")

    get home_path
    assert_match(/data-theme="light"/, response.body)

    get profile_path(other.username)
    assert_match(/data-theme="light"/, response.body)
  end

  # -------------------------------------------------------------- accounts

  test "signing in registers the account for switching" do
    get settings_path

    assert_response :success
    assert_match(/@settings_one/, response.body)
    assert_match(/Current/, response.body)
  end

  test "a second sign-in adds the account to the switcher" do
    sign_in(create_user(username: "second_one"))

    get accounts_path
    assert_response :success
    assert_match(/@settings_one/, response.body)
    assert_match(/@second_one/, response.body)
  end

  test "switching changes the signed-in account without a password" do
    other = create_user(username: "switch_target")
    sign_in(other)

    # Back to the first account, then switch to the second.
    sign_in(@me)
    post switch_account_path(other.id)
    assert_response :redirect

    follow_redirect!
    assert_match(%r{class="account-link" href="/u/switch_target"}, response.body)
  end

  test "an account that was never signed in here cannot be switched to" do
    stranger = create_user(username: "stranger_one")

    post switch_account_path(stranger.id)
    assert_response :redirect

    follow_redirect!
    assert_match(/not connected to this browser/, response.body)
    # The top-bar identity is the proof of who is actually signed in; the
    # stranger may legitimately appear in the suggestions rail.
    assert_match(%r{class="account-link" href="/u/settings_one"}, response.body)
  end

  test "forging the account id does not reach another account" do
    other = create_user(username: "forged_target")
    # `other` was created but never signed into this browser, so it must not be
    # reachable even though the request supplies its real id.
    post switch_account_path(other.id), params: { id: other.id }
    assert_response :redirect

    follow_redirect!
    assert_match(/not connected to this browser/, response.body)
    refute_match(%r{class="account-link" href="/u/forged_target"}, response.body)
  end

  test "removing an account forgets it without signing the current one out" do
    other = create_user(username: "removable_one")
    sign_in(other)
    sign_in(@me)

    delete forget_account_path(other.id)
    assert_response :redirect

    get accounts_path
    refute_match(/@removable_one/, response.body)
    assert_match(/@settings_one/, response.body)
  end

  test "removing the active account falls back to another connected one" do
    other = create_user(username: "fallback_one")
    sign_in(other)
    sign_in(@me)

    delete forget_account_path(@me.id)
    assert_response :redirect

    follow_redirect!
    assert_match(%r{class="account-link" href="/u/fallback_one"}, response.body)
  end

  test "removing the only account signs the browser out" do
    delete forget_account_path(@me.id)
    assert_response :redirect

    get settings_path
    assert_response :redirect
    assert_match(%r{/login}, response.location)
  end

  test "the accounts link is always offered so a second account can be added" do
    get home_path
    assert_match(%r{href="/accounts"}, response.body)

    sign_in(create_user(username: "link_second"))
    get home_path
    assert_match(%r{href="/accounts"}, response.body)
  end

  # -------------------------------------------------------------- messages

  test "delete my messages removes only the ones the member sent" do
    other = create_user(username: "dm_other")
    conversation = DmConversation.between(@me, other)
    conversation.dm_messages.create!(sender: @me, body: "mine to delete")
    conversation.dm_messages.create!(sender: other, body: "theirs to keep")

    delete clear_messages_path
    assert_response :redirect

    bodies = conversation.dm_messages.reload.map(&:body)
    refute_includes bodies, "mine to delete"
    assert_includes bodies, "theirs to keep"
  end

  test "delete my messages never touches another member's sent messages" do
    first = create_user(username: "dm_first")
    second = create_user(username: "dm_second")
    conversation = DmConversation.between(first, second)
    conversation.dm_messages.create!(sender: first, body: "first sent this")

    delete clear_messages_path

    assert_equal [ "first sent this" ], conversation.dm_messages.reload.map(&:body)
  end

  test "deleting every message in a thread drops the now-empty conversation" do
    other = create_user(username: "dm_empty")
    conversation = DmConversation.between(@me, other)
    conversation.dm_messages.create!(sender: @me, body: "only mine")

    delete clear_messages_path

    refute DmConversation.exists?(conversation.id)
  end

  test "a conversation with their message left is kept" do
    other = create_user(username: "dm_kept")
    conversation = DmConversation.between(@me, other)
    conversation.dm_messages.create!(sender: @me, body: "mine")
    conversation.dm_messages.create!(sender: other, body: "theirs")

    delete clear_messages_path

    assert DmConversation.exists?(conversation.id)
  end

  test "delete my messages reports how many were removed" do
    other = create_user(username: "dm_count")
    conversation = DmConversation.between(@me, other)
    2.times { |i| conversation.dm_messages.create!(sender: @me, body: "count #{i}") }

    delete clear_messages_path

    follow_redirect!
    assert_match(/Deleted 2 messages/, response.body)
  end

  test "delete my messages is audited" do
    other = create_user(username: "dm_audit")
    DmConversation.between(@me, other).dm_messages.create!(sender: @me, body: "audit me")

    assert_difference -> { AuditLog.where(action: "user.messages_cleared").count }, 1 do
      delete clear_messages_path
    end
  end

  test "the messages section is on the settings page" do
    get settings_path

    assert_match(/Delete all my messages/, response.body)
  end

  # ------------------------------------------------------- access control

  test "settings is not reachable while signed out" do
    delete logout_path

    get settings_path
    assert_response :redirect
    assert_match(%r{/login}, response.location)
  end

  test "the accounts screen is not reachable while signed out" do
    delete logout_path

    get accounts_path
    assert_response :redirect
    assert_match(%r{/login}, response.location)
  end

  test "clearing messages while signed out changes nothing" do
    other = create_user(username: "dm_signedout")
    conversation = DmConversation.between(@me, other)
    conversation.dm_messages.create!(sender: @me, body: "untouched")

    delete logout_path
    delete clear_messages_path

    assert_equal [ "untouched" ], conversation.dm_messages.reload.map(&:body)
  end
end
