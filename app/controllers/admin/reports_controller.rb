module Admin
  class ReportsController < AdminController
    before_action :require_view_permission, only: [ :index ]
    before_action :require_resolve_permission, only: [ :resolve ]

    def index
      @state = params[:state].to_s.strip
      @state = "open" if @state.blank?
      @category = params[:category].to_s.strip
      @sort = params[:sort].to_s.strip

      scope = Report.includes(:user, :reporter, :tweet, :resolved_by).recent
      scope = scope.where(state: @state) if Report::STATES.include?(@state)
      scope = scope.where(category: @category) if Report::CATEGORIES.key?(@category)

      rows = scope.limit(200).to_a
      # Age is the table's natural order, not severity. Risk ordering is the
      # default; oldest-first stays available for an operator working a backlog
      # that predates the signal this scores on.
      if @sort == "oldest"
        @reports = rows.reverse
      else
        @sort = "risk"
        @reports = RiskScore.rank(rows)
      end

      @counts = Report::STATES.index_with { |state| Report.where(state: state).count }
      @open_count = @counts["open"]
    end

    def resolve
      report = Report.find_by(id: params[:id])

      if report.nil?
        return redirect_to admin_reports_path, alert: "Report not found."
      end

      if report.resolved?
        return redirect_to admin_reports_path, alert: "That report is already closed."
      end

      state = params[:decision].to_s
      state = "actioned" unless %w[actioned dismissed].include?(state)

      report.resolve!(state: state, actor: current_user, note: params[:note].to_s.strip)
      audit!("reports.resolve", target: "report:#{report.id}",
                                detail: "#{state} for user:#{report.user_id}")

      redirect_to admin_reports_path, notice: "Report #{state}."
    end

    private

    def require_view_permission
      require_permission!("reports.view")
    end

    def require_resolve_permission
      require_permission!("reports.resolve")
    end
  end
end
