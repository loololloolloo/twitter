class MessagesController < ApplicationController
  before_action :require_login!

  def index
    # Every account you have a conversation with, most recent first.
    @conversations = DmConversation
                     .where("user_a_id = :id OR user_b_id = :id", id: current_user.id)
                     .includes(:user_a, :user_b, :dm_messages)

    @conversations = @conversations.sort_by do |conversation|
      conversation.dm_messages.maximum(:created_at) || conversation.created_at
    end.reverse
  end

  def show
    @other = User.find_by(id: params[:id])
    return render(plain: "Not found", status: :not_found) unless @other

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
end