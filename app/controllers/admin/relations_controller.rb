module Admin
  # The block and mute graph. Mutes are invisible to the muted account and
  # blocks are mutual, so neither side of an abuser's arrangement is visible
  # from a profile. Reading the graph as a table is how an operator spots the
  # pattern: one account blocked by many, or a pair blocking each other.
  #
  # Read-only by design. Removing someone else's block would change what their
  # own timeline shows, which is not a moderation action.
  class RelationsController < AdminController
    def index
      return refuse unless can?("relations.view")

      @tab = params[:tab] == "mutes" ? "mutes" : "blocks"
      @search = params[:q].to_s.strip

      if @tab == "mutes"
        @rows = Mute.includes(:muter, :muted).recent
        @rows = filter(@rows, "mutes") if @search.present?
      else
        @rows = Block.includes(:blocker, :blocked).recent
        @rows = filter(@rows, "blocks") if @search.present?
      end

      @rows = @rows.limit(300)
    end

    private

    # A term matches either side of the row, so an operator can ask "what has
    # this account blocked" and "who has blocked this account" with one box.
    def filter(rows, table)
      if table == "mutes"
        rows.joins("JOIN users muters ON muters.id = mutes.muter_id")
            .joins("JOIN users muteds ON muteds.id = mutes.muted_id")
            .where("muters.username LIKE :t OR muteds.username LIKE :t", t: "%#{@search}%")
      else
        rows.joins("JOIN users blockers ON blockers.id = blocks.blocker_id")
            .joins("JOIN users blockeds ON blockeds.id = blocks.blocked_id")
            .where("blockers.username LIKE :t OR blockeds.username LIKE :t", t: "%#{@search}%")
      end
    end

    def refuse
      redirect_to admin_root_path, alert: "You do not have the relations.view permission."
    end
  end
end
