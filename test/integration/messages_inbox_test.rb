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
end
