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

    # The same filtered list the index shows, as a CSV download so an operator
    # can keep a record off the machine.
    def export
      unless can?("audit.view")
        return redirect_to(admin_root_path, alert: "You do not have the audit.view permission.")
      end

      entries = AuditLog.includes(:actor).recent.limit(5_000)
      csv = CSV.generate do |rows|
        rows << %w[id when actor action target detail]
        entries.each do |entry|
          rows << [ entry.id, entry.created_at.iso8601, entry.actor&.username,
                    entry.action, entry.target, entry.detail ]
        end
      end

      audit!("audit.export", target: "audit", detail: "exported #{entries.size} entr(ies)")
      send_data csv, filename: "audit-#{Date.current}.csv", type: "text/csv"
    end
  end
end