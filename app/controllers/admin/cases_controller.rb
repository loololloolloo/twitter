module Admin
  # Cases: one investigation standing in for a pile of reports.
  #
  # Reports arrive independently and each is closed on its own. When the same
  # account or post is reported several times, an operator opens a case, links
  # the related reports to it, and records one decision for the whole matter.
  # The case is what turns "37 open reports about @spammer" into a single thing
  # with a single rationale.
  #
  # Separation of duties applies to the decision: the operator who opened the
  # case is not the one who decides it. The bar is enforced in
  # `ModerationCase#decide!` and stated on the case page, because an operator
  # who is excluded should see why rather than a form that refuses them.
  class CasesController < AdminController
    before_action :require_view_permission, only: [ :index, :show ]
    before_action :require_open_permission, only: [ :create ]
    before_action :require_link_permission, only: [ :link ]
    before_action :require_decide_permission, only: [ :decide ]

    def index
      @state = params[:state].to_s.strip
      @state = "open" unless ModerationCase::STATES.include?(@state) || @state == "all"

      scope = ModerationCase.includes(:user, :tweet, :opened_by, :decided_by).recent
      scope = scope.where(state: @state) if @state != "all"

      @cases = scope.limit(200)
      @counts = ModerationCase::STATES.index_with { |state| ModerationCase.where(state: state).count }
      @open_count = @counts["open"]
      @all_count = ModerationCase.count

      # Deep links from a report or an account land here with the subject
      # already filled in, so opening a case from where the problem was seen
      # does not mean retyping an id.
      @prefill_user_id = params[:user_id].to_s
      @prefill_tweet_id = params[:tweet_id].to_s
      @prefill_report_ids = Array(params[:report_ids]).map(&:to_i)
      @linkable = Report.where(state: "open")
                        .where.not(id: CaseLink.select(:report_id))
                        .includes(:user, :reporter, :tweet)
                        .recent
                        .limit(100)
    end

    def show
      @case = ModerationCase.includes(:user, :tweet, :opened_by, :decided_by).find_by(id: params[:id])
      return render_not_found("That case does not exist.") unless @case

      @reports = @case.reports.includes(:user, :reporter, :tweet).recent
      @origin = params[:from].to_s

      # The reports not yet on any case, which is what the link picker offers.
      # A report can only be on one case, so the ones already linked elsewhere
      # are excluded here rather than refused on submit.
      @linkable = Report.where(state: "open")
                        .where.not(id: CaseLink.select(:report_id))
                        .includes(:user, :reporter, :tweet)
                        .recent
                        .limit(100)
    end

    # Open a case about an account, a post, or both, from the case list or
    # straight from an account. The subject is at least one of the two; a case
    # with no subject cannot be linked back to anything.
    def create
      user = User.find_by(id: params[:user_id]) if params[:user_id].present?
      tweet = Tweet.find_by(id: params[:tweet_id]) if params[:tweet_id].present?

      if user.nil? && tweet.nil?
        return redirect_to admin_cases_path, alert: "A case needs an account or a post as its subject."
      end

      title = params[:title].to_s.strip
      if title.blank?
        return redirect_to return_path(user, tweet), alert: "Give the case a title."
      end

      moderation_case = ModerationCase.new(
        user: user,
        tweet: tweet,
        title: title,
        summary: params[:summary].to_s.strip,
        opened_by: current_user
      )

      unless moderation_case.save
        return redirect_to return_path(user, tweet),
                           alert: moderation_case.errors.full_messages.to_sentence
      end

      # The reports named on the opening form are linked in the same step, so
      # a case opened from the queue starts with the cluster already attached.
      link_ids = normalize_report_ids(params[:report_ids])
      linked = attach(moderation_case, link_ids)

      audit!("cases.open", target: "case:#{moderation_case.id}",
                          detail: "#{moderation_case.subject_label}: #{title}" \
                                  "#{linked.positive? ? " (#{linked} report(s) linked)" : ''}")

      redirect_to admin_case_path(moderation_case), notice: "Case ##{moderation_case.id} opened."
    end

    # Attach reports to an existing case. Re-linking a report that is already
    # on this case is a no-op; a report on another case is moved, which the
    # unique index makes explicit rather than silently duplicating.
    def link
      moderation_case = ModerationCase.find_by(id: params[:id])
      return redirect_to admin_cases_path, alert: "Case not found." unless moderation_case

      if moderation_case.decided?
        return redirect_to admin_case_path(moderation_case),
                           alert: "A decided case cannot take new reports."
      end

      ids = normalize_report_ids(params[:report_ids])
      if ids.empty?
        return redirect_to admin_case_path(moderation_case), alert: "Select at least one report to link."
      end

      linked = attach(moderation_case, ids)

      if linked.zero?
        return redirect_to admin_case_path(moderation_case),
                           alert: "Those reports are already on this case."
      end

      audit!("cases.link", target: "case:#{moderation_case.id}",
                          detail: "linked #{linked} report(s) to case ##{moderation_case.id}")

      redirect_to admin_case_path(moderation_case), notice: "Linked #{linked} report#{'s' if linked != 1}."
    end

    def decide
      moderation_case = ModerationCase.find_by(id: params[:id])
      return redirect_to admin_cases_path, alert: "Case not found." unless moderation_case

      if moderation_case.decided?
        return redirect_to admin_case_path(moderation_case), alert: "That case is already decided."
      end

      # The model refuses a barred operator too; checking here turns the
      # refusal into a message on the case instead of an error screen.
      if moderation_case.barred_for?(current_user)
        return redirect_to admin_case_path(moderation_case), alert: moderation_case.bar_reason(current_user)
      end

      decision = params[:decision].to_s
      unless ModerationCase::DECISIONS.key?(decision)
        return redirect_to admin_case_path(moderation_case), alert: "Choose an outcome for the case."
      end

      note = params[:note].to_s.strip
      if note.blank?
        return redirect_to admin_case_path(moderation_case), alert: "A rationale is required to decide a case."
      end

      moderation_case.decide!(decision: decision, actor: current_user, note: note)

      audit!("cases.decide", target: "case:#{moderation_case.id}",
                             detail: "#{decision} case ##{moderation_case.id} " \
                                     "(#{moderation_case.subject_label}): #{note}")

      redirect_to admin_case_path(moderation_case), notice: "Case #{decision}."
    end

    private

    # Links each id that is not already on this case. Returns how many were
    # newly attached, so a submission that changed nothing can say so rather
    # than reporting a count it did not achieve.
    def attach(moderation_case, ids)
      existing = moderation_case.case_links.pluck(:report_id)
      (ids - existing).each do |report_id|
        CaseLink.create!(moderation_case: moderation_case, report_id: report_id, linked_by: current_user)
      end
      (ids - existing).size
    end

    # Report ids arrive as a list of form values. Non-numeric entries are
    # dropped rather than coerced, and the list is de-duplicated and clipped to
    # reports that actually exist, so a stale or tampered form cannot fail.
    def normalize_report_ids(raw)
      ids = Array(raw).map(&:to_s).select { |id| id.match?(/\A\d+\z/) }.map(&:to_i).uniq
      return [] if ids.empty?

      Report.where(id: ids).pluck(:id)
    end

    def return_path(user, tweet)
      if user
        admin_user_path(user)
      elsif tweet
        admin_tweets_path(q: tweet.id)
      else
        admin_cases_path
      end
    end

    def require_view_permission
      require_permission!("cases.view")
    end

    def require_open_permission
      require_permission!("cases.open")
    end

    def require_link_permission
      require_permission!("cases.link")
    end

    def require_decide_permission
      require_permission!("cases.decide")
    end
  end
end
