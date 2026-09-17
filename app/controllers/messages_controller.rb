class MessagesController < ApplicationController
  before_action :require_login!

  def index
    @conversations = conversation_list
  end

  def show
    @other = User.find_by(id: params[:id])
    return render(plain: "Not found", status: :not_found) unless @other

    # The list stays visible beside the open thread, so it is built here too.
    # Only a recent window is rendered: an account can hold thousands of
    # conversations, and the full list belongs on the inbox itself.
    @conversations = conversation_sidebar(@other)
    @conversation = DmConversation.between(current_user, @other)
    @messages = @conversation.dm_messages.chronological
  end

  def create
    @other = User.find_by(id: params[:id])
    return render(plain: "Not found", status: :not_found) unless @other

    body = params[:body].to_s.strip
    conversation = DmConversation.between(current_user, @other)

    if body.blank?
      redirect_to conversation_path(@other)
      return
    end

    conversation.dm_messages.create!(sender: current_user, body: body)

    redirect_to conversation_path(@other)
  end

  private

  # Every account you have a conversation with, most recent first.
  def conversation_list
    conversations = DmConversation
                    .where("user_a_id = :id OR user_b_id = :id", id: current_user.id)
                    .includes(:user_a, :user_b, :dm_messages)

    conversations.sort_by do |conversation|
      conversation.dm_messages.maximum(:created_at) || conversation.created_at
    end.reverse
  end

  # The window shown beside an open thread: the most recent handful, plus the
  # thread being read so its row can be highlighted even when it is older.
  SIDEBAR_LIMIT = 30

  def conversation_sidebar(open_with)
    recent = conversation_list.first(SIDEBAR_LIMIT)
    return recent if recent.any? { |c| c.other_for(current_user).id == open_with.id }

    current = conversation_list.find { |c| c.other_for(current_user).id == open_with.id }
    current ? recent << current : recent
  end
end