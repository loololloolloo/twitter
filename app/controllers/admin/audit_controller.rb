module Admin
  class AuditController < AdminController
    def index
      unless can?("audit.view")
        return redirect_to(admin_root_path, alert: "You do not have the audit.view permission.")
      end

      @search = params[:q].to_s.strip
      scope = AuditLog.includes(:actor).recent

      if @search.present?
        scope = scope.where("action LIKE :term OR target LIKE :term OR detail LIKE :term",
                            term: "%#{@search}%")
      end

      @entries = scope.limit(300)
    end
  end
end