# Shared gate for every /admin screen. Each action declares the permission it
# needs with `require_permission!`, so a moderator with only a few grants can
# reach the parts they own and nothing else.
class AdminController < ApplicationController
  before_action :require_login!
  before_action :require_admin_panel!
  before_action :load_open_report_count

  layout "admin"

  helper_method :rank_of, :outranks?

  private

  # The Reports tab carries the open-queue count, so it is loaded once here
  # rather than by each screen that happens to want it.
  def load_open_report_count
    return unless can?("reports.view")

    @open_reports_nav = Report.open.count
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
end