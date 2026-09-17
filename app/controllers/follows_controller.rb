class FollowsController < ApplicationController
  before_action :require_login!
  before_action :load_target

  def create
    if @target.id == current_user.id
      redirect_back fallback_location: profile_path(@target.username),
                    alert: "You cannot follow yourself."
      return
    end

    Follow.find_or_create_by!(follower: current_user, followee: @target)
    Notification.create!(user: @target, actor: current_user, kind: "follow",
                         body: "@#{current_user.username} followed you")
    audit!("user.follow", target: "user:#{@target.id}", detail: "@#{current_user.username} followed @#{@target.username}")

    redirect_to profile_path(@target.username)
  end

  def destroy
    current_user.active_follows.where(followee_id: @target.id).delete_all

    redirect_to profile_path(@target.username)
  end

  private

  def load_target
    @target = User.find_by("username = ? COLLATE NOCASE", params[:username])
    return if @target

    render plain: "Not found", status: :not_found
  end
end