module Admin
  class UsersController < AdminController
    before_action :require_permission_for_action
    before_action :load_user, only: [ :show, :ban, :unban, :suspend, :destroy,
                                       :update_role, :toggle_verified, :set_followers,
                                       :update_email, :update_tags, :impersonate,
                                       :warn, :revoke_warning ]
    # Every action that writes to the target account has to clear the owner
    # check. `show` is not in this list: the owner account is still viewable,
    # it just has nothing on it that can change it.
    before_action :require_may_manage!, only: [ :ban, :unban, :suspend, :destroy,
                                                :update_role, :toggle_verified,
                                                :set_followers, :update_email,
                                                :update_tags, :impersonate,
                                                :warn, :revoke_warning ]

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
      @reports = Report.where(user_id: @user.id).includes(:reporter).recent.limit(20)
      @open_reports = @reports.count(&:open?)
      @warnings = @user.user_warnings.includes(:actor).recent.limit(50)
      @active_warnings = @warnings.count(&:active?)
      @warning_choices = warning_duration_choices
      @moderation_history = moderation_history
    end

    # Issue a warning. A warning is deliberately not a sanction: it records that
    # the account was told, and nothing about the account changes. The reason is
    # required because a warning with no reason is unreadable to the next
    # operator, and the category is validated against the model's own list.
    def warn
      unless can?("users.warn")
        return redirect_to(admin_user_path(@user), alert: "You do not have the users.warn permission.")
      end

      if @user.id == current_user.id
        return redirect_to(admin_user_path(@user), alert: "You cannot warn your own account.")
      end

      reason = params[:reason].to_s.strip
      if reason.blank?
        return redirect_to(admin_user_path(@user), alert: "A warning reason is required.")
      end

      category = params[:category].presence_in(UserWarning::CATEGORIES.keys) || "other"
      expires = warning_expiry(params[:duration].presence || "none")

      @user.user_warnings.create!(
        actor: current_user,
        category: category,
        reason: reason,
        expires_at: expires
      )

      label = expires ? "expires in #{humanize_until(expires)}" : "no expiry"
      audit!("users.warn", target: "user:#{@user.id}",
                           detail: "warned (#{category}), #{label}: #{reason}")
      redirect_to admin_user_path(@user), notice: "Warning issued."
    end

    # Withdraw a warning that should not count against the account. The row is
    # kept rather than deleted so the trail still shows that it was given and
    # then revoked.
    def revoke_warning
      unless can?("users.warn")
        return redirect_to(admin_user_path(@user), alert: "You do not have the users.warn permission.")
      end

      warning = @user.user_warnings.find_by(id: params[:warning_id])
      return redirect_to(admin_user_path(@user), alert: "Unknown warning.") if warning.nil?

      if warning.expired?
        return redirect_to(admin_user_path(@user), alert: "That warning has already expired.")
      end

      warning.update!(expires_at: Time.current)
      audit!("users.warn", target: "user:#{@user.id}",
                           detail: "revoked warning ##{warning.id}")
      redirect_to admin_user_path(@user), notice: "Warning revoked."
    end

    # The tag toggles on the user page. The form always carries the whole set, so a
    # flag that is absent from the submission is one the operator cleared rather
    # than one they left alone. Every change is recorded with its new value.
    def update_tags
      unless can?("users.tags")
        return redirect_to(admin_user_path(@user), alert: "You do not have the users.tags permission.")
      end

      changed = []
      User::ACCOUNT_TAGS.each_key do |column|
        wanted = params[column].present?
        next if @user.public_send(column) == wanted

        @user.update!(column => wanted)
        changed << "#{column}=#{wanted}"
      end

      note = params[:tag_note].to_s.strip
      if @user.tag_note != note
        @user.update!(tag_note: note)
        changed << "tag_note updated"
      end

      if changed.empty?
        redirect_to admin_user_path(@user), notice: "No tag changes."
      else
        audit!("users.tags", target: "user:#{@user.id}", detail: changed.join(", "))
        redirect_to admin_user_path(@user), notice: "Tags updated."
      end
    end

    # Log in as another member. Restricted to accounts the operator outranks, so
    # this cannot be used to take over a peer or the owner; the original
    # operator id is stashed in the session so the impersonation can be ended.
    def impersonate
      unless can?("users.impersonate")
        return redirect_to(admin_user_path(@user), alert: "You do not have the users.impersonate permission.")
      end

      if @user.id == current_user.id
        return redirect_to(admin_user_path(@user), alert: "You are already signed in as this account.")
      end

      unless outranks?(@user)
        return redirect_to(admin_user_path(@user),
                           alert: "You cannot impersonate a user at or above your own level.")
      end

      audit!("users.impersonate", target: "user:#{@user.id}", detail: "started as @#{@user.username}")
      session[:impersonator_id] = current_user.id
      session[:user_id] = @user.id

      redirect_to home_path, notice: "You are now browsing as @#{@user.username}."
    end

    # Ends an impersonation and returns the operator to the panel.
    def stop_impersonating
      operator_id = session[:impersonator_id]
      unless operator_id
        return redirect_to home_path, alert: "You are not impersonating anyone."
      end

      operator = User.find_by(id: operator_id)
      session.delete(:impersonator_id)

      if operator.nil?
        session.delete(:user_id)
        return redirect_to login_path, alert: "The operator account no longer exists."
      end

      session[:user_id] = operator.id
      AuditLog.record(actor: operator, action: "users.impersonate.end", detail: "returned to own account")
      redirect_to admin_root_path, notice: "Impersonation ended."
    end

    # The panel gate asks `admin.access` of whoever is signed in, which while
    # impersonating is the member, not the operator. Ending an impersonation
    # therefore has to bypass that check or the operator can never get back.
    def skip_admin_panel_gate?
      action_name == "stop_impersonating"
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

      # Only the owner may hand out a role at or above their own level, and
      # nobody may demote the owner: the owner's role is the top of the ladder,
      # so every other role would be a demotion and would hand the instance to
      # whoever did it.
      if !current_user.owner? && role.rank >= rank_of(current_user)
        return redirect_to(admin_user_path(@user),
                           alert: "You cannot assign a role at or above your own level.")
      end

      if @user.owner? && !role.owner?
        return redirect_to(admin_user_path(@user),
                           alert: "The owner account cannot be moved to another role.")
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
      audit!("users.followers", target: "user:#{@user.id}",
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
      "set_followers" => "users.followers",
      "update_email" => "users.email",
      "warn" => "users.warn", "revoke_warning" => "users.warn"
    }.freeze

    def require_permission_for_action
      key = ACTION_PERMISSIONS[action_name]
      require_permission!(key) if key
    end

    def load_user
      @user = User.includes(:role).find_by(id: params[:id])
      return if @user

      render_not_found
    end

    # Every moderation action taken against this account, newest first, in one
    # list. The audit trail below it is the raw record and stays as it is; this
    # is the same events reduced to what happened, who did it and what it
    # applies to, so an account's sanction history can be read without decoding
    # action keys.
    #
    # Warnings are read from their own table rather than the audit trail because
    # a warning carries state the trail cannot: it can expire or be revoked, and
    # its row needs the controls for that. Everything else comes from the trail,
    # which is the only source that records the actor and the exact time.
    def moderation_history
      entries = @warnings.map do |warning|
        {
          tone: warning.active? ? "warn" : "quiet",
          label: "Warning: #{warning.category_label}",
          actor: warning.actor,
          at: warning.created_at,
          detail: warning.reason,
          state: warning_state(warning),
          warning: warning
        }
      end

      AuditLog.includes(:actor).where(target: "user:#{@user.id}").recent.limit(200).each do |entry|
        next unless MODERATION_ACTIONS.key?(entry.action)

        entries << {
          tone: MODERATION_ACTIONS[entry.action][:tone],
          label: MODERATION_ACTIONS[entry.action][:label],
          actor: entry.actor, at: entry.created_at,
          detail: entry.detail, state: nil, warning: nil
        }
      end

      entries.sort_by { |entry| entry[:at] || Time.current }.reverse
    end

    # The action keys that count as moderation, with how each one reads in the
    # history. Anything not listed here stays only in the raw audit trail.
    # `users.warn` is deliberately absent: warnings render from their own rows,
    # so listing it here would show every warning twice.
    MODERATION_ACTIONS = {
      "users.ban"      => { tone: "bad",  label: "Ban changed" },
      "users.suspend"  => { tone: "bad",  label: "Suspension changed" },
      "users.roles"    => { tone: "info", label: "Role changed" },
      "users.verify"   => { tone: "info", label: "Verified badge changed" },
      "users.tags"     => { tone: "info", label: "Account tags changed" },
      "users.email"    => { tone: "info", label: "Email changed" },
      "users.followers" => { tone: "info", label: "Follower count changed" },
      "users.delete"   => { tone: "bad",  label: "Account deleted" }
    }.freeze

    # A warning's own status line: when it lapses, whether it has, or whether it
    # is still standing.
    def warning_state(warning)
      return "expired" if warning.expired?

      warning.expires_at ? "expires #{humanize_until(warning.expires_at)}" : "no expiry"
    end
  end
end