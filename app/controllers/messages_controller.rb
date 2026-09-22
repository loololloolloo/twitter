class MessagesController < ApplicationController
  before_action :require_login!
  # A conversation is stored with the lower user id first, so messaging
  # yourself would address one row to the same account twice; it is refused
  # before any thread is built rather than left to the picker.
  before_action :refuse_self_message, only: %i[create compose]

  def index
    @conversations = conversation_list
    @recipient_query = params[:to].to_s.strip
    @recipient = recipient_for(@recipient_query)
    @recipients = User.not_suspended.where.not(id: current_user.id).order(:username)
  end

  def show
    @other = User.find_by(id: params[:id])
    return render_not_found unless @other

    # The list stays visible beside the open thread, so it is built here too.
    # Only a recent window is rendered: an account can hold thousands of
    # conversations, and the full list belongs on the inbox itself.
    @conversations = conversation_sidebar(@other)
    @conversation = DmConversation.between(current_user, @other)
    @messages = @conversation.dm_messages.chronological
  end

  # Posting from a thread's compose box is addressed by account id.
  def create
    @other = User.find_by(id: params[:id])
    return render_not_found unless @other

    deliver
  end

  # Posting from the inbox header's picker, which names an account by handle
  # rather than id. An unresolved picker falls back to the inbox with a note
  # rather than a 404, because the account may simply have mistyped the handle.
  def compose
    @other = recipient_for(params[:to])

    if @other.nil?
      flash[:alert] = "We could not find that account. Check the username and try again."
      redirect_to messages_path(to: params[:to]) and return
    end

    deliver
  end

  private

  def refuse_self_message
    other = params[:id].present? ? User.find_by(id: params[:id]) : recipient_for(params[:to])
    return unless other == current_user

    flash[:alert] = "You cannot send a message to yourself."
    redirect_to messages_path and return
  end

  # The write shared by both compose entry points, so a message started in the
  # picker is stored exactly as one sent from an open thread.
  def deliver
    body = params[:body].to_s.strip
    conversation = DmConversation.between(current_user, @other)

    if body.blank?
      redirect_to conversation_path(@other)
      return
    end

    conversation.dm_messages.create!(sender: current_user, body: body)

    redirect_to conversation_path(@other)
  end

  # Resolves the inbox picker's typed value to an account. A leading @ is
  # tolerated because handles are quoted that way, and the search is
  # case-insensitive so the handle does not have to be reproduced exactly.
  # Account ids are deliberately not accepted: the picker offers handles, and
  # an id would let the form address an account the operator never named.
  def recipient_for(value)
    handle = value.to_s.strip.sub(/\A@/, "")
    return nil if handle.blank?

    User.where("LOWER(username) = ?", handle.downcase).first
  end

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