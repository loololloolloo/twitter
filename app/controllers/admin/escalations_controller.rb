module Admin
  # The escalation queue. This is the panel's answer to the Cross-Check idea:
  # a set of accounts that are handled differently from the rest, pulled out of
  # the ordinary user list so they are reviewed as a group.
  #
  # Two distinct populations are shown, and they are kept apart because they
  # mean different things:
  #
  #   * Consult-before-acting flags - an account an operator must not touch
  #     without the policy team's sign-off.
  #   * Visibility limits - accounts carrying a search or trends blacklist, or
  #     marked do-not-amplify. The account still works; its reach is cut.
  class EscalationsController < AdminController
    def index
      return refuse unless can?("escalations.view")

      @tab = %w[review limits].include?(params[:tab]) ? params[:tab] : "review"

      @review = User.includes(:role).where(requires_review: true).order(id: :asc)
      @limits = User.includes(:role).reach_limited.order(id: :asc)
    end

    private

    def refuse
      redirect_to admin_root_path, alert: "You do not have the escalations.view permission."
    end
  end
end
