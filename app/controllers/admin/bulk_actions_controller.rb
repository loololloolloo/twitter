# Bulk actions on the accounts list.
#
# Two steps, deliberately. The list posts a selection here and this screen
# states the exact blast radius before anything is written; only a second,
# confirmed POST runs it. A bulk destructive action cannot be undone by looking
# at the row again, so the confirmation is the feature rather than a formality.
#
# The controller only ever receives account ids. Every account is re-read and
# re-checked against the same guards the single-account screen uses, so a
# tampered selection cannot reach the owner or a peer.
module Admin
  class BulkActionsController < AdminController
    CONFIRMATION_WORD = "CONFIRM".freeze

    before_action :require_bulk_permissions
    before_action :load_action
    before_action :load_targets

    def new
      return unless prepare

      @confirm_word = CONFIRMATION_WORD
    end

    def create
      return unless prepare

      unless params[:confirm].to_s.strip.casecmp?(CONFIRMATION_WORD)
        return redirect_to admin_users_path,
                           alert: "Type #{CONFIRMATION_WORD} to run a bulk action."
      end

      applied = BulkUserAction.apply(@plan, current_user, reason: @reason)

      # The per-account entries each record their own target; this one records
      # the run itself, so the trail shows that a batch happened as well as
      # what it did to each account.
      AuditLog.record(actor: current_user, action: "users.bulk.#{@action.key}",
                      target: "accounts",
                      detail: "#{applied.size} account(s) #{@action.past_verb}: #{@plan.summary}" \
                              "#{@reason.present? ? " - #{@reason}" : ''}")

      redirect_to admin_users_path,
                  notice: "#{applied.size} account#{'s' if applied.size != 1} #{@action.past_verb}."
    end

    private

    # The page itself has its own grant: entering the bulk workstream is a
    # deliberate per-role decision, not something implied by holding delete or
    # suspend. The action then needs its own permission too, checked below, so
    # a bulk run cannot borrow the grant of a different action.
    def require_bulk_permissions
      return if can?("users.bulk")

      redirect_to admin_users_path,
                  alert: "Bulk actions are not enabled for your account."
    end

    def load_action
      @action = BulkUserAction.fetch(params[:action_key])

      unless @action
        redirect_to admin_users_path, alert: "Choose an action for the selected accounts."
        return
      end

      return if can?(@action.permission)

      redirect_to admin_users_path,
                  alert: "You are not allowed to #{@action.active_verb} accounts."
    end

    # The accounts named in the selection, in a stable order. Ids that are not
    # whole numbers are dropped rather than coerced, and a missing row is
    # simply absent, so a stale form cannot fail the run.
    def load_targets
      ids = Array(params[:ids]).map(&:to_s).select { |id| id.match?(/\A\d+\z/) }.map(&:to_i).uniq
      @users = ids.empty? ? [] : User.includes(:role).where(id: ids).order(:username)

      return if @users.any?

      redirect_to admin_users_path, alert: "Select at least one account."
    end

    # Reads the request into `@tag`, `@reason` and `@plan`. Nothing here writes,
    # so the confirmation screen and the run share it. Returns false after
    # redirecting when the submission is not complete.
    #
    # The tag is only required to run, not to preview: the list cannot know
    # which tag is wanted until the operator is on the confirmation screen, so
    # the picker lives there.
    def prepare
      @tag = params[:tag].to_s
      @reason = params[:reason].to_s.strip

      if action_name == "create"
        if BulkUserAction.tag?(@action.key) && !User::ACCOUNT_TAGS.key?(@tag)
          redirect_to admin_users_path, alert: "Choose which tag to apply."
          return false
        end

        if BulkUserAction::REASON_REQUIRED.include?(@action.key) && @reason.blank?
          redirect_to admin_users_path, alert: "A reason is required for that action."
          return false
        end
      end

      @tag = nil unless User::ACCOUNT_TAGS.key?(@tag)
      @plan = BulkUserAction.plan(@action.key, @users, current_user, tag: @tag)
      true
    end
  end
end
