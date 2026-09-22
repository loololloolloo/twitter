module Admin
  class PermissionsController < AdminController
    def index
      unless can?("users.permissions")
        return redirect_to(admin_root_path, alert: "You do not have the users.permissions permission.")
      end

      @roles = Role.order(rank: :desc)
      @permissions = Permission.order(:id)
      @matrix = Role.includes(:permissions).each_with_object({}) do |role, hash|
        hash[role.id] = role.permissions.map(&:key).to_set
      end
      @recent_changes = PermissionChange.includes(:role, :actor).recent.limit(8)
    end

    def update
      unless can?("users.permissions")
        return redirect_to(admin_root_path, alert: "You do not have the users.permissions permission.")
      end

      role = Role.find_by(id: params[:role_id])

      if role.nil?
        return redirect_to(admin_permissions_path, alert: "Unknown role.")
      end

      # The owner role is intentionally not editable: granting one permission
      # fewer would leave the instance with no way to restore full control.
      if role.name == Role::OWNER
        return redirect_to(admin_permissions_path, alert: "The owner role cannot be edited.")
      end

      granted = Array(params[:permissions]).map(&:to_s) & Permission::KEYS.keys
      before = role.permission_keys
      role.permission_ids = Permission.where(key: granted).pluck(:id)

      # The audit trail records that the set was saved; this row records what
      # the save moved, so the review surface can show the capability diff. A
      # save that changes nothing writes no row and is still audited.
      change = PermissionChange.record(
        role: role, actor: current_user, before: before,
        after: role.permission_keys, note: params[:note]
      )

      detail = "set #{granted.size} permissions"
      detail += "; +#{change.added.size}/-#{change.removed.size} (#{change.summary})" if change
      audit!("users.permissions", target: "role:#{role.id}", detail: detail)

      if change
        redirect_to admin_permissions_path,
                    notice: "#{role.name} permissions updated: #{change.summary}."
      else
        redirect_to admin_permissions_path, notice: "#{role.name} permissions unchanged."
      end
    end
  end
end