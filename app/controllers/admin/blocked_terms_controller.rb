module Admin
  # The blocked-terms list. Each row is a term the site acts on, and the screen
  # is built around one fact: "flag" and "hide" have very different blast radii.
  # A flagged post stays up and is only marked in the panel; a hidden post is
  # gone from every timeline for every reader. The mode is therefore stated in
  # plain words next to every row, together with how many posts the term matches
  # right now, so setting one is a decision made with the effect in view rather
  # than discovered afterwards.
  #
  # The matcher the timeline uses is compiled from this list and cached; every
  # write here rebuilds it, so the change takes effect on the next request
  # without rescanning posts on every request.
  class BlockedTermsController < AdminController
    before_action :require_view_permission, only: [ :index ]
    before_action :require_manage_permission, only: [ :create, :toggle ]

    def index
      @terms = BlockedTerm.recent.limit(500)
      @active_count = BlockedTerm.active.count
      @hide_count = BlockedTerm.active.where(mode: "hide").count
      @flag_count = BlockedTerm.active.where(mode: "flag").count

      # The posts a "flag" term is meant to surface. Hidden ones are already
      # gone from the site, so listing them here as well would only repeat what
      # the count beside the term already says.
      @flagged_posts = flagged_posts
    end

    def create
      term = BlockedTerm.new(
        term: params[:term].to_s.strip,
        mode: params[:mode].presence_in(BlockedTerm::MODES.keys) || "flag",
        category: params[:category].presence_in(BlockedTerm::CATEGORIES.keys) || "other",
        note: params[:note].to_s.strip,
        created_by_id: current_user.id
      )

      if term.save
        audit!("settings.blocked_terms", target: "blocked_term:#{term.id}",
                                         detail: "added #{term.mode} term #{term.term.inspect}")
        redirect_to admin_blocked_terms_path, notice: "#{term.mode_label} added for #{term.term.inspect}."
      else
        redirect_to admin_blocked_terms_path, alert: term.errors.full_messages.to_sentence
      end
    end

    # Turning a term off keeps the row: an operator needs to see that the rule
    # existed and who set it, and removing the row would take that with it.
    def toggle
      term = BlockedTerm.find_by(id: params[:id])

      if term.nil?
        return redirect_to admin_blocked_terms_path, alert: "Term not found."
      end

      term.update!(active: !term.active)
      audit!("settings.blocked_terms", target: "blocked_term:#{term.id}",
                                       detail: "#{term.active ? 'enabled' : 'disabled'} #{term.mode} term #{term.term.inspect}")
      redirect_to admin_blocked_terms_path,
                  notice: "#{term.term.inspect} #{term.active ? 'is now active' : 'is now off'}."
    end

    private

    # Flagged posts, newest first. This is the review surface the "flag" mode
    # exists for, and it is read through the normal includes so the panel shows
    # the same post the timeline does.
    def flagged_posts
      return Tweet.none if @flag_count.zero?

      Tweet.includes(:user).matching_flags.recent.limit(50)
    end

    def require_view_permission
      require_permission!("settings.view")
    end

    def require_manage_permission
      require_permission!("settings.blocked_terms")
    end
  end
end
