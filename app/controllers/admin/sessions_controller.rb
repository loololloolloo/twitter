module Admin
  # Active sessions across the site. A hijacked account is usually detected here
  # rather than on the account page: the operator sees a token they do not
  # recognise, on an account whose owner has lost control of it, and can end
  # that one session without signing the whole site out.
  #
  # Revoking is the only write. Every revocation is audited with the account and
  # the token's tail, so a session that comes back is traceable.
  class SessionsController < AdminController
    def index
      return refuse unless can?("sessions.view")

      @search = params[:q].to_s.strip
      @only_active = params[:state] != "all"

      scope = Session.includes(:user)
      scope = scope.active if @only_active

      if @search.present?
        scope = scope.joins(:user).where(
          "users.username LIKE :term OR users.email LIKE :term OR sessions.token LIKE :term",
          term: "%#{@search}%"
        )
      end

      @sessions = scope.order(expires_at: :desc).limit(300)
    end

    def destroy
      return refuse unless can?("sessions.view")

      session_row = Session.find_by(id: params[:id])
      return redirect_to(admin_sessions_path, alert: "Session not found.") if session_row.nil?

      owner = session_row.user
      session_row.destroy!
      audit!("sessions.revoke", target: "user:#{owner.id}",
                                detail: "ended a session for @#{owner.username}")

      redirect_to admin_sessions_path, notice: "Session ended for @#{owner.username}."
    end

    # Every session belonging to one account, which is the fastest way to cut a
    # suspected takeover without touching anyone else.
    def destroy_for_user
      return refuse unless can?("sessions.view")

      account = User.find_by(id: params[:id])
      return redirect_to(admin_sessions_path, alert: "Account not found.") if account.nil?

      removed = Session.where(user_id: account.id).delete_all
      audit!("sessions.revoke_all", target: "user:#{account.id}",
                                    detail: "ended #{removed} session(s) for @#{account.username}")

      redirect_to admin_sessions_path, notice: "Ended #{removed} session(s) for @#{account.username}."
    end

    private

    def refuse
      redirect_to admin_root_path, alert: "You do not have the sessions.view permission."
    end
  end
end
