# Shared gate for every /admin screen. Each action declares the permission it
# needs with `require_permission!`, so a moderator with only a few grants can
# reach the parts they own and nothing else.
class AdminController < ApplicationController
  before_action :require_login!
  before_action :require_admin_panel!
  before_action :load_open_report_count
  before_action :load_toolbar_counts

  layout "admin"

  helper_method :rank_of, :outranks?, :may_manage?

  private

  # The Reports tab carries the open-queue count, so it is loaded once here
  # rather than by each screen that happens to want it.
  def load_open_report_count
    return unless can?("reports.view")

    @open_reports_nav = Report.open.count
  end

  # The toolbar tabs carry their own live counts. Each is gated on the
  # permission that lets the operator open the tab, so nobody is shown a number
  # for a queue they cannot reach.
  def load_toolbar_counts
    @escalation_count = User.where(requires_review: true).count if can?("escalations.view")
    @active_session_count = Session.active.count if can?("sessions.view")
  end

  def require_admin_panel!
    return if can?("admin.access")
    # A controller may exempt an action from the gate; ending an impersonation
    # is the case that needs it, since the acting session is the member's.
    return if respond_to?(:skip_admin_panel_gate?, true) && send(:skip_admin_panel_gate?)

    # require_login! has already run, so a direct redirect beats bouncing
    # through the root route, which itself redirects signed-in users.
    redirect_to home_path, alert: "You do not have access to the admin panel."
  end

  def require_permission!(key)
    return if can?(key)

    redirect_to admin_root_path, alert: "You do not have the #{key} permission."
  end

  def rank_of(user)
    user.role.rank
  end

  # True when the acting user may moderate the target: strictly higher rank,
  # or acting on themselves where the legacy panel allowed it.
  def outranks?(target)
    rank_of(current_user) > rank_of(target)
  end

  # The instance owner account is the one account the panel cannot touch from
  # the outside. It answers to nobody, so every mutating action has to ask this
  # before it writes. Rank alone is not enough: an admin's rank is above a
  # plain member's, so the role-change guard would happily let them demote the
  # owner to "user" and take the instance over.
  def may_manage?(target)
    return true unless target.owner?

    target.id == current_user.id
  end

  # Gate for the actions that would otherwise let staff alter the owner
  # account. Redirects rather than raising, so the operator lands back on the
  # card with an explanation instead of an error screen.
  def require_may_manage!
    return if may_manage?(@user)

    redirect_to admin_user_path(@user),
                alert: "The @#{@user.username} account can only be changed by signing in as it."
  end
end