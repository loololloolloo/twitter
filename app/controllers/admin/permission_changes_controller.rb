module Admin
  class PermissionChangesController < AdminController
    # Role edits are reviewed on their own surface rather than only in the
    # audit log, because the log records that a save happened while this screen
    # answers what capability moved. Reading it is the same grant as reading
    # the audit trail: both expose the security posture of every role, so an
    # operator trusted with one is trusted with the other.
    def index
      require_permission!("permissions.review")

      # Only the edits that actually changed something are stored, so the list
      # is the real history rather than every save of the editor form.
      @changes = PermissionChange.includes(:role, :actor).recent.limit(200)
      @roles = Role.order(rank: :desc)
      @filter_role_id = params[:role_id].to_s
      if @filter_role_id.present?
        @changes = @changes.where(role_id: @filter_role_id)
      end
    end
  end
end
