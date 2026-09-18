# Lists: curated timelines of accounts, read without following them.
#
# Every action is scoped through `current_user.lists`, so one account can never
# edit another's list by guessing an id. That is the whole authorization story
# here - there is no list an account can see but not own, except a public one it
# can read.
class ListsController < ApplicationController
  before_action :require_login!
  before_action :load_own_list, only: [ :edit, :update, :destroy, :members, :add_member, :remove_member ]
  before_action :load_visible_list, only: [ :show ]

  def index
    @lists = current_user.lists.recent
    @subscribed = list_memberships_of_others
  end

  def show
    @members = @list.members.order(:username).limit(100)
    @tweets = @list.timeline(limit: 100).readable_by(current_user)
  end

  def new
    @list = current_user.lists.new
  end

  def create
    @list = current_user.lists.new(list_params)

    if @list.save
      audit!("list.create", target: "list:#{@list.id}", detail: "created list #{@list.name}")
      redirect_to list_path(@list), notice: "Your list was created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @list.update(list_params)
      audit!("list.update", target: "list:#{@list.id}", detail: "updated list #{@list.name}")
      redirect_to list_path(@list), notice: "Your list was updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    name = @list.name
    @list.destroy!
    audit!("list.destroy", target: "list:#{@list.id}", detail: "deleted list #{name}")

    redirect_to lists_path, notice: "Your list was deleted."
  end

  def members
    @members = @list.members.order(:username).limit(100)

    # Candidates are accounts the list does not already hold. Blocked accounts
    # are excluded so a list cannot be used to follow someone you have blocked.
    existing = @list.list_memberships.select(:user_id)
    @candidates = User.visible
                      .where.not(id: current_user.id)
                      .where.not(id: existing)
                      .where.not(id: current_user.hidden_account_ids)
                      .order(:username)
                      .limit(50)
  end

  def add_member
    member = User.find_by("username = ? COLLATE NOCASE", params[:username].to_s.delete_prefix("@"))
    return redirect_to(list_members_path(@list), alert: "No such account.") if member.nil?
    return redirect_to(list_members_path(@list), alert: "You cannot add that account.") if member.id == current_user.id

    @list.list_memberships.find_or_create_by!(user_id: member.id)
    redirect_to list_members_path(@list), notice: "@#{member.username} was added to the list."
  end

  def remove_member
    @list.list_memberships.where(user_id: params[:user_id]).delete_all
    redirect_to list_members_path(@list), notice: "Removed from the list."
  end

  private

  # A list owned by the signed-in account. Anything else is a 404 rather than a
  # forbidden, so a probe cannot tell whether an id exists.
  #
  # The member routes are nested, so they name the list `list_id`; the resource
  # routes name it `id`. Both are read here so one loader serves all of them.
  def load_own_list
    @list = current_user.lists.find_by(id: params[:list_id].presence || params[:id])
    return if @list

    render_not_found
  end

  # A list the signed-in account may read: its own, or a public one. A private
  # list of another account is not readable.
  def load_visible_list
    @list = List.find_by(id: params[:id])
    if @list.nil? || (@list.user_id != current_user.id && @list.is_private)
      return render_not_found
    end

    @is_owner = @list.user_id == current_user.id
  end

  def list_memberships_of_others
    ListMembership.where(user_id: current_user.id)
                  .joins(:list)
                  .where.not(lists: { user_id: current_user.id })
                  .includes(:list)
                  .map(&:list)
  end

  def list_params
    permitted = params.require(:list).permit(:name, :description)

    {
      name: permitted[:name].to_s.strip,
      description: permitted[:description].to_s.strip,
      is_private: params.dig(:list, :is_private).to_s == "1"
    }
  end
end