class SettingsController < ApplicationController
  before_action :require_login!

  SECTIONS = %w[account security privacy notifications preferences accessibility data].freeze

  def edit
    @section = params[:panel].presence_in(SECTIONS) || "account"
  end

  def update
    attributes = {
      display_name: params[:display_name].to_s.strip.presence || current_user.username,
      bio: params[:bio].to_s.strip.first(160),
      location: params[:location].to_s.strip.first(60),
      website: params[:website].to_s.strip.first(200)
    }

    # An upload replaces the current picture; omitting the file leaves it
    # untouched so saving the form does not clear an existing avatar.
    previous_avatar = current_user.avatar_path
    previous_banner = current_user.banner_path

    avatar = Uploads.store(params[:avatar], current_user.id, scope: "avatars")
    banner = Uploads.store(params[:banner], current_user.id, scope: "banners")

    attributes[:avatar_path] = avatar if avatar.present?
    attributes[:banner_path] = banner if banner.present?

    if current_user.update(attributes)
      # The replaced files would otherwise sit in public/uploads forever, since
      # nothing else tracks them once the row stops pointing at them.
      Uploads.remove(previous_avatar) if avatar.present? && previous_avatar != avatar
      Uploads.remove(previous_banner) if banner.present? && previous_banner != banner

      audit!("user.settings", target: "user:#{current_user.id}", detail: "updated profile settings")
      redirect_to settings_redirect_path, notice: "Your profile has been updated."
    else
      # The new files were written before validation; if the update failed they
      # would be orphans, so drop them.
      Uploads.remove(avatar) if avatar.present?
      Uploads.remove(banner) if banner.present?
      flash.now[:error] = current_user.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end

  def password
    unless current_user.password_matches?(params[:current_password])
      redirect_to settings_redirect_path, alert: "Your current password is incorrect."
      return
    end

    password = params[:password].to_s

    if password.length < 8
      redirect_to settings_redirect_path, alert: "Your new password must be at least 8 characters."
      return
    end

    if password != params[:password_confirm].to_s
      redirect_to settings_redirect_path, alert: "The new passwords did not match."
      return
    end

    current_user.update!(password_hash: PasswordDigest.hash(password))
    audit!("user.password", target: "user:#{current_user.id}", detail: "changed password")
    redirect_to settings_redirect_path, notice: "Your password has been changed."
  end

  # The appearance section has no form of its own; the two links carry the
  # theme they want and this writes it. Only the two known values are stored,
  # so the parameter cannot put arbitrary markup into the root element.
  def theme
    theme = User::THEMES.include?(params[:theme].to_s) ? params[:theme].to_s : "light"
    current_user.update!(theme: theme)

    redirect_to settings_redirect_path, notice: "Appearance updated."
  end

  # Which era of the client the account sees. Like `theme` this reads a value
  # from a set rather than storing what was sent, so the parameter can neither
  # invent a design nor put markup into the root element.
  def design
    design = User::DESIGNS.include?(params[:design].to_s) ? params[:design].to_s : User::DEFAULT_DESIGN
    current_user.update!(design: design)

    redirect_to settings_redirect_path, notice: "Design updated."
  end

  # Protecting an account is a privacy setting, not a moderation one, so it
  # lives here. Turning it on does not remove the followers already approved;
  # turning it off does not approve anyone who is waiting, which is the same
  # behaviour the client had.
  def privacy
    current_user.update!(protected: params[:protected].to_s == "1")

    audit!("user.privacy", target: "user:#{current_user.id}",
                           detail: current_user.protected? ? "protected account" : "public account")

    notice = if current_user.protected?
      "Your Tweets are now protected. New followers must be approved by you."
    else
      "Your Tweets are now public."
    end

    redirect_to settings_redirect_path, notice: notice
  end

  # Deletes the messages the signed-in member sent. This is not an admin power -
  # messages received from other people are left alone, and the scope is pinned
  # to `current_user` so no id from the request can widen it.
  def clear_messages
    sent = DmMessage.where(sender_id: current_user.id)
    removed = sent.count

    # Empty conversations would otherwise linger in the inbox with nothing in
    # them, so any thread this empties is dropped as well.
    conversation_ids = sent.distinct.pluck(:dm_conversation_id)
    sent.delete_all

    DmConversation.where(id: conversation_ids).find_each do |conversation|
      conversation.destroy! if conversation.dm_messages.none?
    end

    audit!("user.messages_cleared", target: "user:#{current_user.id}",
                                     detail: "deleted #{removed} sent messages")
    redirect_to settings_redirect_path, notice: "Deleted #{removed} #{'message'.pluralize(removed)} you sent."
  end

  # Deletes every tweet the signed-in member has posted. Like the message
  # version this is not an admin power: the scope is pinned to `current_user`,
  # so no id from the request can widen it. Tweets are soft-deleted, matching
  # the per-tweet button and the admin delete, so the rows survive for audit and
  # other people's replies and retweets to them degrade rather than dangle.
  def clear_tweets
    authored = Tweet.where(user_id: current_user.id, is_deleted: false)
    removed = authored.count

    authored.update_all(is_deleted: true, updated_at: Time.current)

    audit!("user.tweets_cleared", target: "user:#{current_user.id}",
                                  detail: "deleted #{removed} tweets")
    redirect_to settings_redirect_path, notice: "Deleted #{removed} #{'tweet'.pluralize(removed)}."
  end

  private

  # A redirect back to settings has to land on the same section the action was
  # fired from, or changing the password from the security panel drops the
  # member on the account panel instead. An unknown panel is dropped rather than
  # reflected, so the parameter cannot steer the redirect anywhere new.
  def settings_redirect_path
    settings_path(panel: params[:panel].presence_in(SECTIONS))
  end
end