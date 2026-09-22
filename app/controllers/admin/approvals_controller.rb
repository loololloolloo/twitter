module Admin
  # The four-eyes approval queue. The panel's highest-impact actions are filed
  # here as pending requests and only take effect once a *different* operator
  # approves them: permanent suspension, email change and handle release. A
  # single operator can propose any of them, but cannot be the one who makes
  # the change real.
  #
  # This queue is a check on the panel's own powers, so each card states what
  # approving it will do to the account in plain words, and the operator who
  # filed the request sees a banner naming them instead of the approve button.
  # The bar is enforced in `ApprovalRequest#decide!`; checking here only turns
  # the refusal into a message on the queue.
  class ApprovalsController < AdminController
    before_action :require_decide_permission, only: [ :index, :decide ]

    def index
      @state = params[:state].to_s.strip
      @state = "pending" unless ApprovalRequest::STATES.include?(@state) || @state == "all"

      scope = ApprovalRequest.includes(:user, :requested_by, :decided_by).recent
      scope = scope.where(state: @state) if @state != "all"

      @requests = scope.limit(200)
      @counts = ApprovalRequest::STATES.index_with { |state| ApprovalRequest.where(state: state).count }
      @pending_count = @counts["pending"]
      @all_count = ApprovalRequest.count
    end

    def decide
      request = ApprovalRequest.includes(:user).find_by(id: params[:id])

      if request.nil?
        return redirect_to admin_approvals_path, alert: "Request not found."
      end

      if request.decided?
        return redirect_to admin_approvals_path, alert: "That request is already decided."
      end

      # The model refuses a self-approval too; checking here only turns the
      # refusal into a message on the queue instead of an error screen.
      if request.barred_for?(current_user)
        return redirect_to admin_approvals_path, alert: request.bar_reason(current_user)
      end

      decision = params[:decision].to_s
      unless ApprovalRequest::DECISIONS.key?(decision)
        return redirect_to admin_approvals_path, alert: "Choose an outcome for the request."
      end

      note = params[:note].to_s.strip
      if decision == "rejected" && note.blank?
        return redirect_to admin_approvals_path, alert: "A reason is required to reject a request."
      end

      request.decide!(decision: decision, actor: current_user, note: note)

      # Approving is what carries the change out; rejecting leaves the account
      # untouched. A rejected request is applied by nothing and goes stale.
      if decision == "approved"
        request.apply!
        audit_application(request)
        audit!("approvals.apply", target: "user:#{request.user_id}",
                                  detail: "applied #{request.action_key}: #{request.change_summary} " \
                                          "(request ##{request.id}, filed by " \
                                          "#{actor_label(request.requested_by)})")
      end

      notify_requester(request, decision)

      audit!("approvals.decide", target: "user:#{request.user_id}",
                                 detail: "#{decision} #{request.action_key} request ##{request.id} " \
                                         "(#{request.change_summary})" \
                                         "#{note.present? ? ": #{note}" : ''}")

      redirect_to admin_approvals_path,
                  notice: "Request #{decision}#{decision == 'approved' ? ' and applied' : ''}."
    end

    private

    # The requester is told either way. An approval that quietly changed the
    # account, or a rejection with no reason, would leave them firing the same
    # request again.
    def notify_requester(request, decision)
      return if request.requested_by.nil?

      body = if decision == "approved"
               "Your approval request (#{request.action_label.downcase}) for " \
               "@#{request.user.username} was approved and applied by #{actor_label(current_user)}."
             else
               "Your approval request (#{request.action_label.downcase}) for " \
               "@#{request.user.username} was rejected by #{actor_label(current_user)}: " \
               "#{request.decision_note}"
             end

      request.requested_by.notifications.create!(actor: current_user, kind: "admin", body: body)
    end

    def actor_label(operator)
      operator ? "@#{operator.username}" : "system"
    end

    def require_decide_permission
      require_permission!("approvals.decide")
    end

    # Applying a request is the operator's action, but the moderation history
    # groups the account's sanctions, emails and handle changes under the action
    # keys the single-operator paths use. Recording those too keeps an approved
    # permanent ban reading as a ban in the history rather than as an opaque
    # "approval applied" row.
    def audit_application(request)
      case request.action_key
      when "permanent_ban"
        audit!("users.ban", target: "user:#{request.user_id}",
                            detail: "banned for permanent: #{request.payload_data['reason']}")
      when "email_change"
        audit!("users.email", target: "user:#{request.user_id}",
                              detail: "changed email to #{request.payload_data['email']}")
      when "handle_release"
        audit!("users.handle", target: "user:#{request.user_id}",
                               detail: "released handle, renamed the account to @#{request.payload_data['handle']}")
      end
    end
  end
end
