class FollowsController < ApplicationController
  before_action :require_login!
  before_action :load_target

  def create
    if @target.id == current_user.id
      redirect_back fallback_location: profile_path(@target.username),
                    alert: "You cannot follow yourself."
      return
    end

    # A block in either direction stops a follow outright. The blocked account
    # must not be able to follow back, and the blocker must not be able to
    # re-follow somebody they blocked.
    if current_user.blocked_with?(@target)
      redirect_back fallback_location: profile_path(@target.username),
                    alert: "You cannot follow @#{@target.username}."
      return
    end

    # A protected account does not gain a follower from this: it gains a request
    # the account has to approve. The follow is created by the approval, so the
    # two states can never both be true.
    if @target.protected?
      request = FollowRequest.find_or_create_by!(requester_id: current_user.id, target_id: @target.id)
      request.update!(state: "pending") unless request.pending?

      Notification.create!(user: @target, actor: current_user, kind: "follow_request",
                           body: "@#{current_user.username} asked to follow you")
      audit!("user.follow_request", target: "user:#{@target.id}",
                                    detail: "@#{current_user.username} requested to follow @#{@target.username}")

      redirect_to profile_path(@target.username),
                  notice: "Your follow request was sent to @#{@target.username}."
      return
    end

    Follow.find_or_create_by!(follower: current_user, followee: @target)
    Notification.create!(user: @target, actor: current_user, kind: "follow",
                         body: "@#{current_user.username} followed you")
    audit!("user.follow", target: "user:#{@target.id}", detail: "@#{current_user.username} followed @#{@target.username}")

    redirect_to profile_path(@target.username)
  end

  # Unfollowing also clears any request that was waiting on the same account,
  # so cancelling a pending ask and unfollowing an approved one are the same
  # gesture from the reader's side.
  def destroy
    current_user.active_follows.where(followee_id: @target.id).delete_all
    current_user.sent_follow_requests.where(target_id: @target.id).delete_all

    redirect_to profile_path(@target.username)
  end

  private

  def load_target
    @target = User.find_by("username = ? COLLATE NOCASE", params[:username])
    return if @target

    render_not_found
  end
end