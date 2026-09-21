module Admin
  # The verification request queue. A member asks for the verified badge; an
  # operator approves or denies it with a reason. Approving is what grants the
  # badge, so the decision and the grant cannot disagree.
  #
  # The decision is a judgement about a public figure, so the screen puts the
  # requester's account signals next to the controls rather than making the
  # operator open the account in another tab: how old the account is, how much
  # it posts, how many people follow it and whether it already carries a limit
  # or an escalation flag. The request body is what the member claims; the
  # signals are what the account shows, and a blind click on the badge is the
  # failure mode this screen exists to prevent.
  class VerificationController < AdminController
    before_action :require_view_permission, only: [ :index ]
    before_action :require_decide_permission, only: [ :decide ]

    def index
      @state = params[:state].to_s.strip
      @state = "pending" unless VerificationRequest::STATES.include?(@state) || @state == "all"

      scope = VerificationRequest.includes(:user, :reviewed_by).recent
      scope = scope.where(state: @state) if @state != "all"

      @requests = scope.limit(200)
      @counts = VerificationRequest::STATES.index_with { |state| VerificationRequest.where(state: state).count }
      @pending_count = @counts["pending"]
      @all_count = VerificationRequest.count
    end

    def decide
      request = VerificationRequest.includes(:user).find_by(id: params[:id])

      if request.nil?
        return redirect_to admin_verification_path, alert: "Request not found."
      end

      if request.decided?
        return redirect_to admin_verification_path, alert: "That request is already decided."
      end

      # The model refuses a self-review too; checking here only turns the
      # refusal into a message on the queue instead of an error screen.
      if request.barred_for?(current_user)
        return redirect_to admin_verification_path, alert: request.bar_reason(current_user)
      end

      decision = params[:decision].to_s
      unless VerificationRequest::DECISIONS.key?(decision)
        return redirect_to admin_verification_path, alert: "Choose an outcome for the request."
      end

      note = params[:note].to_s.strip
      if decision == "denied" && note.blank?
        return redirect_to admin_verification_path, alert: "A reason is required to deny a request."
      end

      # The badge is granted by the decision, but the owner account is the one
      # account the panel cannot change from the outside, so the grant has to
      # clear the same guard every other write does.
      if decision == "approved" && !may_manage?(request.user)
        return redirect_to admin_verification_path,
                           alert: "The @#{request.user.username} account can only be changed by signing in as it."
      end

      request.decide!(decision: decision, actor: current_user, note: note)

      notify_member(request, decision)

      audit!("verification.decide", target: "user:#{request.user_id}",
                                    detail: "#{decision} verification request ##{request.id} " \
                                            "(#{request.category_label})" \
                                            "#{note.present? ? ": #{note}" : ''}")

      redirect_to admin_verification_path, notice: "Verification request #{decision}."
    end

    private

    # The member is told the outcome in their own notifications. The reason is
    # carried through verbatim: a denial the member cannot read is not a
    # decision they can respond to.
    def notify_member(request, decision)
      body = if decision == "approved"
               "Your verification request was approved. The badge is now on your profile."
             else
               "Your verification request was denied. #{request.decision_note}"
             end

      request.user.notifications.create!(actor: current_user, kind: "admin", body: body)
    end

    def require_view_permission
      require_permission!("verification.view")
    end

    def require_decide_permission
      require_permission!("verification.decide")
    end
  end
end
