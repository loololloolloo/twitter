module Admin
  # The appeals queue. An appeal contests a ban that another operator imposed,
  # so this screen is defined by a separation-of-duties rule: the operator who
  # imposed the sanction may not decide its appeal. The bar is enforced in
  # `Appeal#decide!` and stated next to the decision controls here, because an
  # operator who is excluded should see why rather than a form that refuses.
  class AppealsController < AdminController
    before_action :require_view_permission, only: [ :index ]
    before_action :require_decide_permission, only: [ :decide ]

    def index
      @state = params[:state].to_s.strip
      @state = "pending" unless Appeal::STATES.include?(@state) || @state == "all"

      scope = Appeal.includes(:user, :sanction_actor, :decided_by).recent
      scope = scope.where(state: @state) if @state != "all"

      @appeals = scope.limit(200)
      @counts = Appeal::STATES.index_with { |state| Appeal.where(state: state).count }
      @pending_count = @counts["pending"]
      @all_count = Appeal.count
    end

    def decide
      appeal = Appeal.includes(:user).find_by(id: params[:id])

      if appeal.nil?
        return redirect_to admin_appeals_path, alert: "Appeal not found."
      end

      if appeal.decided?
        return redirect_to admin_appeals_path, alert: "That appeal is already decided."
      end

      # The model refuses a barred operator too; checking here only turns the
      # refusal into a message on the queue instead of an error screen.
      if appeal.barred_for?(current_user)
        return redirect_to admin_appeals_path, alert: appeal.bar_reason(current_user)
      end

      decision = params[:decision].to_s
      unless Appeal::DECISIONS.key?(decision)
        return redirect_to admin_appeals_path, alert: "Choose an outcome for the appeal."
      end

      appeal.decide!(decision: decision, actor: current_user, note: params[:note].to_s.strip)

      notify_member(appeal, decision)

      audit!("appeals.decide", target: "appeal:#{appeal.id}",
                               detail: "#{decision} #{appeal.sanction_label.downcase} for " \
                                       "user:#{appeal.user_id} (sanction by " \
                                       "#{appeal.sanction_actor ? "@#{appeal.sanction_actor.username}" : 'unknown'})")

      redirect_to admin_appeals_path, notice: "Appeal #{decision}."
    end

    private

    # The member is told the outcome in their own notifications. A reversed
    # appeal is the one that matters most: the account needs to know the
    # sanction was lifted, and by whom, or it stays away on its own.
    def notify_member(appeal, decision)
      appeal.user.notifications.create!(
        actor: current_user,
        kind: "admin",
        body: "Your appeal of the #{appeal.sanction_label.downcase} was #{decision}. " \
              "#{appeal.decision_note}".strip
      )
    end

    def require_view_permission
      require_permission!("appeals.view")
    end

    def require_decide_permission
      require_permission!("appeals.decide")
    end
  end
end