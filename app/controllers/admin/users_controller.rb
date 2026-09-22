module Admin
  class UsersController < AdminController
    before_action :require_permission_for_action
    before_action :load_user, only: [ :show, :ban, :unban, :suspend, :destroy,
                                       :update_role, :toggle_verified, :set_followers,
                                       :update_email, :release_handle, :update_tags, :impersonate,
                                       :warn, :revoke_warning, :apply_template,
                                       :add_note, :pin_note, :destroy_note ]
    # Every action that writes to the target account has to clear the owner
    # check. `show` is not in this list: the owner account is still viewable,
    # it just has nothing on it that can change it. Filing an approval request
    # is a write to the request queue rather than the account, and the account
    # it names cannot be one the operator is barred from managing.
    before_action :require_may_manage!, only: [ :ban, :unban, :suspend, :destroy,
                                                :update_role, :toggle_verified,
                                                :set_followers, :update_email,
                                                :release_handle,
                                                :update_tags, :impersonate,
                                                :warn, :revoke_warning, :apply_template,
                                                :add_note, :pin_note, :destroy_note ]

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
      @bulk_actions = can?("users.bulk") ? BulkUserAction.allowed_for(current_user) : []
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
      @active_warnings = @user.strike_count
      @strike_rung = @user.strike_rung
      @next_strike_rung = @user.next_strike_rung
      @warning_choices = warning_duration_choices
      @moderation_history = moderation_history
      @notes = @user.staff_notes.includes(:author).ordered
      @approvals = @user.approval_requests.includes(:requested_by, :decided_by).recent.limit(20)
      @pending_approvals = @user.approval_requests.pending.to_a
      # Keyed by action so the controls below can show which of them already
      # has a request waiting. The model refuses a second one, so the screen
      # has to be able to say why the form is not the way forward this time.
      @pending_approval_by_action = @pending_approvals.index_by(&:action_key)
      # The macros this operator can actually apply. Filtered by the action's
      # own permission, so the picker never offers an action the operator would
      # then be refused - the list is what they can do, not what exists.
      @enforcement_templates = EnforcementTemplate.active.order(:name)
                                                  .select { |template| can?(template.permission) }
    end

    # Leave an internal note on an account. The note is read-only context for
    # the next operator: it is attributed and dated, it never notifies the
    # member and it changes nothing about the account.
    def add_note
      unless can?("users.notes")
        return redirect_to(admin_user_path(@user), alert: "You do not have the users.notes permission.")
      end

      if @user.id == current_user.id
        return redirect_to(admin_user_path(@user), alert: "You cannot note your own account.")
      end

      body = params[:body].to_s.strip

      if body.blank?
        return redirect_to(admin_user_path(@user), alert: "A note cannot be empty.")
      end

      if body.length > StaffNote::MAX_BODY
        return redirect_to(admin_user_path(@user),
                           alert: "A note is limited to #{StaffNote::MAX_BODY} characters.")
      end

      note = @user.staff_notes.create!(
        author: current_user,
        body: body,
        pinned: params[:pinned].present?
      )

      audit!("users.notes", target: "user:#{@user.id}",
                            detail: "added note ##{note.id}: #{note.body.truncate(120)}")
      redirect_to admin_user_path(@user), notice: "Note added."
    end

    # Pin a note so standing context stays at the top of the record however much
    # incidental commentary accumulates beneath it.
    def pin_note
      unless can?("users.notes")
        return redirect_to(admin_user_path(@user), alert: "You do not have the users.notes permission.")
      end

      note = @user.staff_notes.find_by(id: params[:note_id])
      return redirect_to(admin_user_path(@user), alert: "Unknown note.") if note.nil?

      note.update!(pinned: !note.pinned)
      audit!("users.notes", target: "user:#{@user.id}",
                            detail: "#{note.pinned ? 'pinned' : 'unpinned'} note ##{note.id}")
      redirect_to admin_user_path(@user), notice: note.pinned ? "Note pinned." : "Note unpinned."
    end

    # Remove a note. Deleting is real rather than a tombstone because a note is
    # a private aside, not a sanction the record has to keep accounting for; the
    # audit trail keeps the fact and the text of the deletion.
    def destroy_note
      unless can?("users.notes")
        return redirect_to(admin_user_path(@user), alert: "You do not have the users.notes permission.")
      end

      note = @user.staff_notes.find_by(id: params[:note_id])
      return redirect_to(admin_user_path(@user), alert: "Unknown note.") if note.nil?

      # The row is gone after this, so the audit detail has to carry what the
      # note said or the trail would record only that something was deleted.
      excerpt = note.body.truncate(120)
      note.destroy!
      audit!("users.notes", target: "user:#{@user.id}",
                            detail: "deleted note ##{note.id}: #{excerpt}")
      redirect_to admin_user_path(@user), notice: "Note deleted."
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

      create_warning(reason: reason, category: category, expires: expires)
      redirect_to admin_user_path(@user), notice: "Warning issued."
    end

    # Apply a canned macro to this account. A macro is wording, not authority:
    # the action it names still runs through the same permission, self-action
    # and rank guards the hand-written form does, so a macro that names a ban
    # does not let a moderator who lacks users.ban ban anyone. The macro only
    # decides the reason and the parameters.
    def apply_template
      template = EnforcementTemplate.active.find_by(id: params[:template_id])
      if template.nil?
        return redirect_to(admin_user_path(@user), alert: "Unknown or disabled macro.")
      end

      unless can?(template.permission)
        return redirect_to(admin_user_path(@user),
                           alert: "You do not have the #{template.permission} permission this macro needs.")
      end

      if @user.id == current_user.id
        return redirect_to(admin_user_path(@user), alert: "You cannot enforce a macro on your own account.")
      end

      case template.action_key
      when "warn"
        create_warning(reason: template.reason, category: template.category,
                       expires: warning_expiry(template.duration))
        notice = "Warning issued from #{template.name.inspect}."
      when "ban"
        unless outranks?(@user)
          return redirect_to(admin_user_path(@user),
                             alert: "You cannot ban a user at or above your own level.")
        end

        expires = ban_expiry(template.duration)
        apply_timed_ban(reason: template.reason, expires: expires)
        notice = "User banned from #{template.name.inspect} (#{humanize_until(expires)})."
      when "suspend"
        return redirect_to(admin_user_path(@user), alert: "That account is already suspended.") if @user.is_suspended
        unless outranks?(@user)
          return redirect_to(admin_user_path(@user),
                             alert: "You cannot suspend a user at or above your own level.")
        end

        @user.update!(is_suspended: true)
        @user.sessions.destroy_all
        audit!("users.suspend", target: "user:#{@user.id}",
                                detail: "applied macro #{template.name.inspect}: suspended")
        notice = "User suspended from #{template.name.inspect}."
      else
        return redirect_to(admin_user_path(@user), alert: "That macro names an unknown action.")
      end

      template.increment!(:uses_count)
      redirect_to admin_user_path(@user), notice: notice
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

      # A permanent ban is the highest-impact sanction the panel can impose -
      # it is what the ban-evasion and sockpuppet investigations end in - so it
      # needs a second operator. A timed ban stays a single-operator action.
      # The reason is filed with the request rather than written to the account,
      # because nothing about the account changes until the request is approved.
      if expires.nil?
        return request_approval(
          action_key: "permanent_ban",
          detail: "permanent ban: #{reason}",
          reason: reason
        )
      end

      apply_timed_ban(reason: reason, expires: expires)
      redirect_to admin_user_path(@user), notice: "User banned (#{humanize_until(expires)})."
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

      # The registered email is the sign-in identifier and the address every
      # account recovery flows through, so rewriting it is a four-eyes action.
      # The change is proposed here and only lands when a different operator
      # approves it. The form carries no reason field, so the proposal states
      # its own justification rather than refusing the operator.
      email_reason = params[:reason].to_s.strip
      email_reason = "email change requested from the account record" if email_reason.blank?

      request_approval(
        action_key: "email_change",
        detail: "email #{@user.email} -> #{email}",
        payload: { email: email },
        reason: email_reason
      )
    end

    # File an approval request for one of the four-eyes actions. The request is
    # what shows on the account and on the approvals queue; nothing about the
    # account changes until a different operator approves it.
    #
    # The reason is recorded on the request rather than only in the audit trail,
    # so the approver reads why without decoding an action key. A duplicate
    # pending request for the same action is refused: two open requests for the
    # same change would let two approvals produce two divergent outcomes.
    def request_approval(action_key:, detail:, reason: nil, payload: {})
      reason = reason.nil? ? params[:reason].to_s.strip : reason.to_s.strip

      action = ApprovalRequest::ACTIONS[action_key]
      unless action
        return redirect_to admin_user_path(@user), alert: "Unknown approval action."
      end

      if reason.blank?
        return redirect_to admin_user_path(@user),
                           alert: "A reason is required to file a #{action.label.downcase} request."
      end

      if ApprovalRequest.exists?(user_id: @user.id, action_key: action_key, state: "pending")
        return redirect_to admin_user_path(@user),
                           alert: "A #{action.label.downcase} request is already pending for @#{@user.username}."
      end

      request = ApprovalRequest.create!(
        user: @user,
        requested_by: current_user,
        action_key: action_key,
        request_note: reason,
        payload: payload.merge(reason: reason).to_json
      )

      audit!("approvals.request", target: "user:#{@user.id}",
                                  detail: "filed #{action_key} (request ##{request.id}): #{detail}")
      redirect_to admin_user_path(@user),
                  notice: "#{action.label} filed for approval. A different operator must approve it."
    end

    # Release an account's handle and claim a new one. A handle is the account's
    # public identity and a released one can be claimed by someone else, so this
    # is a four-eyes action like the other irreversible ones. The chosen handle
    # travels in the request payload; approving it is what actually renames the
    # account.
    def release_handle
      handle = params[:handle].to_s.strip
      taken = User.where.not(id: @user.id).where("username = ? COLLATE NOCASE", handle).exists?

      if handle.blank? || taken
        return redirect_to(admin_user_path(@user),
                           alert: "Choose an available handle for @#{@user.username}.")
      end

      request_approval(
        action_key: "handle_release",
        detail: "release @#{@user.username} as @#{handle}",
        payload: { handle: handle },
        reason: "handle release requested from the account record"
      )
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
      "release_handle" => "users.handle",
      "warn" => "users.warn", "revoke_warning" => "users.warn",
      "add_note" => "users.notes", "pin_note" => "users.notes",
      "destroy_note" => "users.notes"
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
      "users.handle"   => { tone: "info", label: "Handle released" },
      "users.followers" => { tone: "info", label: "Follower count changed" },
      "users.delete"   => { tone: "bad",  label: "Account deleted" }
    }.freeze

    # A warning's own status line: when it lapses, whether it has, or whether it
    # is still standing.
    def warning_state(warning)
      return "expired" if warning.expired?

      warning.expires_at ? "expires #{humanize_until(warning.expires_at)}" : "no expiry"
    end

    # Tells the member, in their own notifications, that a warning was placed on
    # the account. The reason is included verbatim because the whole point of a
    # warning is that the account was told why; a notification that says only
    # "you were warned" is not a warning. The actor is carried so the notice is
    # attributed, and the strike count is stated so the member is not surprised
    # by the next consequence.
    def notify_warning(warning)
      count = @user.strike_count
      rung = @user.strike_rung
      state = warning.expires_at ? "expires in #{humanize_until(warning.expires_at)}" : "does not expire"

      body = "Warning: #{warning.category_label} (#{state}). Reason: #{warning.reason} " \
             "Standing warnings: #{count}#{rung ? " (#{rung.label})" : ''}."

      @user.notifications.create!(actor: current_user, kind: "admin", body: body)
    end

    # The warning write shared by the hand-written form and a macro, so a macro
    # cannot produce a warning the form would not: same row, same notification,
    # same audit entry. The caller has already cleared the permission and
    # self-action guards.
    def create_warning(reason:, category:, expires:)
      warning = @user.user_warnings.create!(
        actor: current_user,
        category: category,
        reason: reason,
        expires_at: expires
      )

      notify_warning(warning)

      label = expires ? "expires in #{humanize_until(expires)}" : "no expiry"
      rung = @user.strike_rung
      audit!("users.warn", target: "user:#{@user.id}",
                           detail: "warned (#{category}), #{label}, strike #{@user.strike_count}" \
                                   "#{rung ? " (#{rung.label})" : ''}: #{reason}")
    end

    # The timed-ban write shared by the form and a macro. Permanent bans are not
    # reachable here: they need a second operator and are filed as a request.
    def apply_timed_ban(reason:, expires:)
      @user.update!(
        is_banned: true,
        ban_reason: reason,
        ban_permanent: false,
        ban_expires_at: expires
      )

      # A banned account keeps its session so the ban screen can explain the
      # ban and offer a log out; the ban gate blocks everything else.
      label = humanize_until(expires)
      audit!("users.ban", target: "user:#{@user.id}", detail: "banned for #{label}: #{reason}")
    end
  end
end
