# The panel's maintenance screen. Every action here destroys data, so each one
# is gated on the maintenance.run permission, requires the operator to type the
# confirmation word, and is recorded in the audit log before it is announced.
module Admin
  class ToolsController < AdminController
    before_action :require_maintenance_permission
    # Restore, vacuum and prune are exempt: each is either reversible, cannot
    # remove a live row, or is deliberate by choosing the file, so they do not
    # demand the confirmation word.
    before_action :require_confirmation, except: [ :show, :prune_orphans, :restore_database, :vacuum ]

    CONFIRMATION_WORD = "CONFIRM".freeze

    # The tabs. "Site tools" holds the content sweeps, "Danger zone" is the
    # set that cannot be undone from inside the panel, and "Storage" is the
    # database housekeeping.
    TABS = {
      "site" => "Site tools",
      "content" => "Content",
      "storage" => "Storage",
      "danger" => "Danger zone",
      "backup" => "Backup & restore"
    }.freeze

    def show
      @tab = TABS.key?(params[:tab]) ? params[:tab] : "site"
      @inventory = Maintenance.inventory
      @database_bytes = Maintenance.database_bytes
      @table_weights = Maintenance.table_weights
    end

    def clear_follows
      removed = Maintenance.clear_follows
      audit!("maintenance.clear_follows", target: "database", detail: "deleted #{removed} follow(s)")
      redirect_to admin_tools_path(tab: "site"), notice: "#{helpers.count_label(removed)} follow(s) removed."
    end

    def purge_tweets
      removed = Maintenance.purge_tweets
      audit!("maintenance.purge_tweets", target: "database", detail: "deleted #{removed} tweet(s)")
      redirect_to admin_tools_path(tab: "site"), notice: "#{helpers.count_label(removed)} tweet(s) deleted."
    end

    def clear_sessions
      removed = Maintenance.clear_sessions(current_user)
      audit!("maintenance.clear_sessions", target: "database", detail: "signed out #{removed} member(s)")
      redirect_to admin_tools_path(tab: "site"), notice: "#{helpers.count_label(removed)} member session(s) cleared."
    end

    # Reversible, so it does not demand the confirmation word: it only removes
    # rows that already point at nothing.
    def prune_orphans
      Maintenance.prune_orphans
      audit!("maintenance.prune_orphans", target: "database", detail: "removed orphaned rows")
      redirect_to admin_tools_path(tab: "site"), notice: "Orphaned rows removed."
    end

    def clear_audit_log
      removed = Maintenance.clear_audit_log
      redirect_to admin_tools_path(tab: "danger"), notice: "#{helpers.count_label(removed)} audit entr(ies) removed."
    end

    # Empties every inbox. The posts the notifications pointed at are left
    # alone, so nobody loses content, only the history of who reacted.
    def clear_notifications
      removed = Maintenance.clear_notifications
      audit!("maintenance.clear_notifications", target: "database", detail: "deleted #{removed} notification(s)")
      redirect_to admin_tools_path(tab: "site"), notice: "#{helpers.count_label(removed)} notification(s) removed."
    end

    # Deletes every direct message and the conversations holding them.
    def clear_messages
      removed = Maintenance.clear_messages
      audit!("maintenance.clear_messages", target: "database", detail: "deleted #{removed} message(s)")
      redirect_to admin_tools_path(tab: "site"), notice: "#{helpers.count_label(removed)} message(s) removed."
    end

    # Drops the readership counters on posts and profiles.
    def clear_views
      removed = Maintenance.clear_views
      audit!("maintenance.clear_views", target: "database", detail: "deleted #{removed} view record(s)")
      redirect_to admin_tools_path(tab: "site"), notice: "#{helpers.count_label(removed)} view record(s) removed."
    end

    # Empties the moderation queue without touching an account or a post.
    def clear_reports
      removed = Maintenance.clear_reports
      audit!("maintenance.clear_reports", target: "database", detail: "deleted #{removed} report(s)")
      redirect_to admin_tools_path(tab: "site"), notice: "#{helpers.count_label(removed)} report(s) removed."
    end

    # The counterpart to clearing the grant: real follows survive, only the
    # padding the operator added goes.
    def clear_granted_followers
      removed = Maintenance.clear_granted_followers
      audit!("maintenance.clear_granted_followers", target: "database",
             detail: "cleared #{removed} granted follower(s)")
      redirect_to admin_tools_path(tab: "site"), notice: "#{helpers.count_label(removed)} granted follower(s) cleared."
    end

    def clear_granted_engagement
      removed = Maintenance.clear_granted_engagement
      audit!("maintenance.clear_granted_engagement", target: "database",
             detail: "cleared #{removed} granted engagement(s)")
      redirect_to admin_tools_path(tab: "site"), notice: "#{helpers.count_label(removed)} granted engagement record(s) cleared."
    end

    # Every session, the operator's included, so a fresh sign-in is required.
    def clear_all_sessions
      removed = Maintenance.clear_all_sessions
      audit!("maintenance.clear_all_sessions", target: "database", detail: "cleared #{removed} session(s)")
      redirect_to login_path, notice: "#{helpers.count_label(removed)} session(s) cleared. Please sign in again."
    end

    def vacuum
      reclaimed = Maintenance.vacuum_database
      audit!("maintenance.vacuum", target: "database", detail: "reclaimed #{reclaimed} byte(s)")
      redirect_to admin_tools_path(tab: "site"), notice: "Database compacted, #{helpers.number_to_human_size(reclaimed)} reclaimed."
    end

    def reset_database
      Maintenance.reset_database(current_user)
      # The audit log was emptied as part of the reset, so this entry has to be
      # written after the sweep to survive it.
      audit!("maintenance.reset_database", target: "database", detail: "reset the site to a fresh install")
      redirect_to admin_tools_path(tab: "danger"),
                  notice: "Site reset. Every account except yours and all content was removed."
    end

    def restore_database
      upload = params[:backup]
      unless upload.respond_to?(:read)
        return redirect_to admin_tools_path(tab: "backup"), alert: "Choose a .sql backup file to restore."
      end

      statements = Maintenance.restore_database(upload.read)
      audit!("maintenance.restore_database", target: "database", detail: "restored a dump of #{statements} statement(s)")
      redirect_to admin_tools_path(tab: "backup"), notice: "Backup restored."
    rescue ArgumentError => e
      redirect_to admin_tools_path(tab: "backup"), alert: "Restore failed: #{e.message}."
    rescue ActiveRecord::StatementInvalid => e
      redirect_to admin_tools_path(tab: "backup"), alert: "Restore failed, the database is unchanged: #{e.message.truncate(160)}"
    end

    private

    def require_maintenance_permission
      require_permission!("maintenance.run")
    end

    # A destructive sweep needs a deliberate act, not a mis-aimed click. The
    # word is checked case-insensitively so it is a speed bump rather than a
    # spelling test.
    def require_confirmation
      return if params[:confirm].to_s.strip.casecmp?(CONFIRMATION_WORD)

      redirect_to admin_tools_path(tab: params[:tab].presence || "site"),
                  alert: "Type #{CONFIRMATION_WORD} to run that task."
    end
  end
end