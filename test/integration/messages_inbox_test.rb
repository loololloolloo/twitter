require "test_helper"

# The 2019 Messages inbox. With no thread open the right pane is the
# placeholder, not a bare heading: a centred envelope over the "Select a
# message" prompt and a line explaining what to do. Once a thread is open the
# placeholder gives way to the conversation.
class MessagesInboxTest < ActionDispatch::IntegrationTest
  test "the inbox placeholder names the envelope and the prompt" do
    me = create_user(username: "inbox_me")
    sign_in(me)

    get messages_path
    assert_response :success
    assert_includes response.body, "dm-empty-state"
    assert_includes response.body, "dm-empty-icon"
    assert_includes response.body, "Select a message"
    assert_includes response.body, "Choose from your existing conversations"
  end

  test "opening a thread replaces the placeholder with the conversation" do
    me = create_user(username: "inbox_me2")
    other = create_user(username: "inbox_other")
    conversation = DmConversation.between(me, other)
    conversation.dm_messages.create!(sender: other, body: "hello there")

    sign_in(me)

    get messages_path
    assert_includes response.body, "dm-empty-state"

    get conversation_path(other)
    assert_response :success
    assert_not_includes response.body, "dm-empty-state"
    assert_includes response.body, "hello there"
  end

  # The 2019 inbox carried a compose control in the header so a conversation
  # could be started without going through a profile first.
  test "the inbox header offers a new-message picker" do
    me = create_user(username: "compose_me")
    sign_in(me)

    get messages_path
    assert_response :success
    assert_includes response.body, "dm-compose"
    assert_includes response.body, "Search for a username"
  end

  test "the picker names the account it resolved from a handle" do
    me = create_user(username: "compose_me2")
    other = create_user(username: "compose_other", display_name: "Other Person")
    sign_in(me)

    get messages_path(to: "@compose_other")
    assert_response :success
    assert_includes response.body, "compose_other"
    assert_includes response.body, "Other Person"
    assert_includes response.body, "dm-compose-new-inline"
  end

  test "the picker says so when no account matches the handle" do
    me = create_user(username: "compose_me3")
    sign_in(me)

    get messages_path(to: "@nobody_here")
    assert_response :success
    assert_includes response.body, "No account is using that username."
    assert_not_includes response.body, "dm-compose-new-inline"
  end

  test "the picker refuses to address the signed-in account" do
    me = create_user(username: "compose_me4")
    sign_in(me)

    get messages_path(to: "@compose_me4")
    assert_response :success
    assert_includes response.body, "You cannot send a message to yourself."
    assert_not_includes response.body, "dm-compose-new-inline"
  end

  test "sending from the picker stores the message and opens the thread" do
    me = create_user(username: "compose_me5")
    other = create_user(username: "compose_target")
    sign_in(me)

    assert_difference -> { DmMessage.count }, 1 do
      post compose_message_path, params: { to: "@compose_target", body: "first contact" }
    end

    assert_redirected_to conversation_path(other)
    conversation = DmConversation.between(me, other)
    message = conversation.dm_messages.sole
    assert_equal "first contact", message.body
    assert_equal me.id, message.sender_id
  end

  test "an unknown handle is reported back on the inbox without a message" do
    me = create_user(username: "compose_me6")
    sign_in(me)

    assert_no_difference -> { DmMessage.count } do
      post compose_message_path, params: { to: "@ghost_account", body: "hello?" }
    end

    assert_redirected_to messages_path(to: "@ghost_account")
    follow_redirect!
    assert_response :success
    assert_includes response.body, "We could not find that account."
  end

  test "the inbox dates each row on the preview line" do
    me = create_user(username: "dated_me")
    other = create_user(username: "dated_other")
    DmConversation.between(me, other).dm_messages.create!(sender: other, body: "recent ping")

    sign_in(me)

    get messages_path
    assert_response :success
    assert_includes response.body, "dm-list-time"
    assert_includes response.body, "recent ping"
    # A message written moments ago reads as "now" rather than a blank cell.
    assert_includes response.body, ">now<"
  end

  test "an empty thread carries no date because there is no arrival to name" do
    me = create_user(username: "undated_me")
    other = create_user(username: "undated_other")
    DmConversation.between(me, other)

    sign_in(me)

    get messages_path
    assert_response :success
    assert_includes response.body, "No messages yet"
    assert_not_includes response.body, "dm-list-time"
  end

  test "the sidebar beside an open thread dates its rows too" do
    me = create_user(username: "sidebar_me")
    other = create_user(username: "sidebar_other")
    DmConversation.between(me, other).dm_messages.create!(sender: other, body: "side note")

    sign_in(me)

    get conversation_path(other)
    assert_response :success
    assert_includes response.body, "dm-list-time"
    assert_includes response.body, "side note"
  end
end
