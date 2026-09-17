module Admin
  class UsersController < AdminController
    before_action :require_permission_for_action
    before_action :load_user, only: [ :show, :ban, :unban, :suspend, :destroy,
                                       :update_role, :toggle_verified, :set_followers,
                                       :update_email ]

    def index
      @search = params[:q].to_s.strip
      @role_filter = params[:role].to_s.strip
      @status = params[:status].to_s.strip

      scope = User.includes(:role).order(:username)

      if @search.present?
        scope = scope.where(
          "username LIKE :term OR display_name LIKE :term OR email LIKE :term",
          term: "%#{@search}%"
        )
      end

      scope = scope.where(role_id: Role.where(name: @role_filter).select(:id)) if @role_filter.present?

      case @status
      when "banned"    then scope = scope.where(is_banned: true)
      when "suspended" then scope = scope.where(is_suspended: true)
      when "verified"  then scope = scope.where(is_verified: true)
      when "bounced"   then scope = scope.email_bounced
      when "inactive"  then scope = scope.email_inactive
      when "protected" then scope = scope.email_protected
      end

      @users = scope.limit(200)
      @roles = Role.order(rank: :desc)
    end

    def show
      @roles = Role.order(rank: :desc)
      @permissions = Permission.order(:id)
      @held = @user.permission_keys
      @tweets = @user.tweets.visible.recent.limit(50)
      @real_followers = Follow.where(followee_id: @user.id).count
      @log = AuditLog.includes(:actor)
                     .where("target = :target OR actor_id = :id", target: "user:#{@user.id}", id: @user.id)
                     .recent.limit(40)
      @ban_choices = ban_duration_choices
    end

    def ban
      if @user.id == current_user.id
        return redirect_to(admin_user_path(@user), alert: "You cannot ban your own account.")
      end

      unless outranks?(@user)
        return redirect_to(admin_user_path(@user),
                           alert: "You cannot ban a user at or above your own level.")
      end

      reason = params[:reason].to_s.strip
      if reason.blank?
        return redirect_to(admin_user_path(@user), alert: "A ban reason is required.")
      end

      expires = ban_expiry(params[:duration].presence || "permanent")

      @user.update!(
        is_banned: true,
        ban_reason: reason,
        ban_permanent: expires.nil?,
        ban_expires_at: expires
      )

      # A banned account keeps its session so the ban screen can explain the
      # ban and offer a log out; the ban gate blocks everything else.
      label = expires ? humanize_until(expires) : "permanent"
      audit!("users.ban", target: "user:#{@user.id}", detail: "banned for #{label}: #{reason}")
      redirect_to admin_user_path(@user), notice: "User banned (#{label})."
    end

    def unban
      @user.update!(is_banned: false, ban_reason: "", ban_permanent: false, ban_expires_at: nil)
      audit!("users.ban", target: "user:#{@user.id}", detail: "unbanned")
      redirect_to admin_user_path(@user), notice: "User unbanned."
    end

    def suspend
      if @user.id != current_user.id && !outranks?(@user)
        return redirect_to(admin_user_path(@user),
                           alert: "You cannot suspend a user at or above your own level.")
      end

      new_state = !@user.is_suspended

      if new_state && @user.id == current_user.id
        return redirect_to(admin_user_path(@user), alert: "You cannot suspend your own account.")
      end

      @user.update!(is_suspended: new_state)
      @user.sessions.destroy_all if new_state

      audit!("users.suspend", target: "user:#{@user.id}", detail: new_state ? "suspended" : "reinstated")
      redirect_to admin_user_path(@user), notice: new_state ? "User suspended." : "User reinstated."
    end

    def update_role
      unless can?("users.roles")
        return redirect_to(admin_user_path(@user), alert: "You do not have the users.roles permission.")
      end

      role = Role.find_by(name: params[:role])

      if role.nil?
        return redirect_to(admin_user_path(@user), alert: "Unknown role.")
      end

      # Only the owner may hand out a role at or above their own level.
      if !current_user.owner? && role.rank >= rank_of(current_user)
        return redirect_to(admin_user_path(@user),
                           alert: "You cannot assign a role at or above your own level.")
      end

      @user.update!(role: role)
      audit!("users.roles", target: "user:#{@user.id}", detail: "set role to #{role.name}")
      redirect_to admin_user_path(@user), notice: "Role updated to #{role.name}."
    end

    def toggle_verified
      new_state = !@user.is_verified
      @user.update!(is_verified: new_state)
      audit!("users.verify", target: "user:#{@user.id}",
                            detail: new_state ? "granted verified badge" : "revoked verified badge")
      redirect_to admin_user_path(@user),
                  notice: new_state ? "Verified badge granted." : "Verified badge revoked."
    end

    # Administrator-granted follower padding, used to make an account look as
    # popular as the operator wants without inventing fake user rows.
    def set_followers
      raw = params[:followers].to_s.strip

      unless raw.match?(/\A\d+\z/)
        return redirect_to(admin_user_path(@user),
                           alert: "Follower count must be a whole number of 0 or more.")
      end

      value = raw.to_i
      @user.update!(bonus_followers: value)
      audit!("users.bot_followers", target: "user:#{@user.id}",
                                    detail: "set follower count to #{value}")
      redirect_to admin_user_path(@user), notice: "Follower count set to #{value}."
    end

    # The identity panel's "Add Email". Email is the sign-in identifier, so it
    # is validated and checked for a collision before it is written; the case
    # check matches the model's own uniqueness rule.
    def update_email
      email = params[:email].to_s.strip

      if email.blank? || !email.match?(URI::MailTo::EMAIL_REGEXP)
        return redirect_to(admin_user_path(@user), alert: "A valid email address is required.")
      end

      taken = User.where.not(id: @user.id).where("email = ? COLLATE NOCASE", email).exists?
      if taken
        return redirect_to(admin_user_path(@user), alert: "That email address is already in use.")
      end

      @user.update!(email: email)
      audit!("users.email", target: "user:#{@user.id}", detail: "set email to #{email}")
      redirect_to admin_user_path(@user), notice: "Email updated."
    end

    def destroy
      if @user.id == current_user.id
        return redirect_to(admin_user_path(@user),
                           alert: "You cannot delete your own account from here.")
      end

      unless outranks?(@user)
        return redirect_to(admin_user_path(@user),
                           alert: "You cannot delete a user at or above your own level.")
      end

      if @user.owner?
        return redirect_to(admin_user_path(@user), alert: "The owner account cannot be deleted.")
      end

      username = @user.username
      @user.destroy!
      audit!("users.delete", target: "user:#{@user.id}", detail: "deleted @#{username}")
      redirect_to admin_users_path, notice: "Deleted @#{username}."
    end

    private

    # Each admin action maps to the permission it needs. A missing mapping
    # denies access rather than allowing it, so a new action is safe by default.
    ACTION_PERMISSIONS = {
      "index" => "users.view", "show" => "users.view",
      "suspend" => "users.suspend", "destroy" => "users.delete",
      "toggle_verified" => "users.verify", "update_role" => "users.roles",
      "ban" => "users.ban", "unban" => "users.ban",
      "set_followers" => "users.bot_followers",
      "update_email" => "users.email"
    }.freeze

    def require_permission_for_action
      key = ACTION_PERMISSIONS[action_name]
      require_permission!(key) if key
    end

    def load_user
      @user = User.includes(:role).find_by(id: params[:id])
      return if @user

      render(plain: "Not found", status: :not_found) and return
    end
  end
end