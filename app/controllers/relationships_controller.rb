# Blocks and mutes, which share a shape: both are a relationship from the
# signed-in account to another, both are created and removed from the same kind
# of page, and both are listed on the same settings screen.
#
# They are one controller because the actions differ by one word; keeping them
# together means the pair of relations cannot drift into behaving differently
# from each other. What differs - the semantics of each - is spelled out in the
# model.
class RelationshipsController < ApplicationController
  before_action :require_login!
  before_action :load_target

  # ---------------------------------------------------------------- blocks

  def block
    if @target.id == current_user.id
      return refuse("You cannot block yourself.")
    end

    if current_user.blocking?(@target)
      return redirect_to(profile_path(@target.username), notice: "You have already blocked @#{@target.username}.")
    end

    current_user.block!(@target)
    audit!("user.block", target: "user:#{@target.id}", detail: "blocked @#{@target.username}")

    redirect_to profile_path(@target.username),
                notice: "You blocked @#{@target.username}. They cannot follow you or see your posts."
  end

  def unblock
    current_user.unblock!(@target)
    audit!("user.unblock", target: "user:#{@target.id}", detail: "unblocked @#{@target.username}")

    redirect_back fallback_location: profile_path(@target.username),
                  notice: "You unblocked @#{@target.username}."
  end

  # ----------------------------------------------------------------- mutes

  def mute
    if @target.id == current_user.id
      return refuse("You cannot mute yourself.")
    end

    current_user.mute!(@target)
    audit!("user.mute", target: "user:#{@target.id}", detail: "muted @#{@target.username}")

    # A mute is private, so the notice is worded as a change to the muter's own
    # view rather than as an action taken against the other account.
    redirect_to profile_path(@target.username),
                notice: "You muted @#{@target.username}. They will not appear in your timeline."
  end

  def unmute
    current_user.unmute!(@target)
    audit!("user.unmute", target: "user:#{@target.id}", detail: "unmuted @#{@target.username}")

    redirect_back fallback_location: profile_path(@target.username),
                  notice: "You unmuted @#{@target.username}."
  end

  private

  def load_target
    @target = User.find_by("username = ? COLLATE NOCASE", params[:username])
    return if @target

    render_not_found
  end

  def refuse(message)
    redirect_back fallback_location: home_path, alert: message
  end
end