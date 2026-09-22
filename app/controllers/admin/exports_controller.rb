module Admin
  # Per-account evidence export. A legal hold or a data-subject request asks for
  # one account's record, its posts and the enforcement history against it, as a
  # single file that can leave the building. This is a disclosure rather than a
  # read, so it is deliberately its own grant and its own screen instead of a
  # button folded into the account record.
  #
  # Every export is recorded twice: once in `data_exports`, which is the durable
  # answer to "who pulled what and why" for the obligation itself, and once in
  # the audit trail, which is the operator-facing log. The reason is required
  # because "exported 12 posts" does not say whether the disclosure was
  # justified.
  class ExportsController < AdminController
    MAX_POSTS = 5_000
    MAX_AUDIT = 5_000

    # The audit actions that are enforcement rather than administration. The
    # account record ships these in a section of their own so the file leads
    # with what was done to the account, not with the raw log. The list is the
    # set of sanctions and the decisions on them; `users.notes` and the other
    # operational actions stay in the appendix.
    ENFORCEMENT_ACTIONS = %w[
      users.ban users.suspend users.warn users.reverse users.roles
      users.verify users.tags users.email users.handle users.followers
    ].freeze

    def index
      return refuse unless can?("exports.run")

      @user = User.includes(:role).find_by(id: params[:user_id])
      return render_not_found if params[:user_id].present? && @user.nil?

      @exports = DataExport.includes(:user, :actor).recent.limit(50)
      @my_exports = @user ? DataExport.where(user_id: @user.id).recent.limit(20) : []
    end

    # Produce the file and record the disclosure. A GET because it is a
    # download, and it is not confirmed because an export changes nothing on
    # the account - it is the record *of* the disclosure that matters.
    def show
      return refuse unless can?("exports.run")

      user = User.includes(:role).find_by(id: params[:user_id])
      return render_not_found if user.nil?

      reason = params[:reason].to_s.strip
      if reason.blank?
        return redirect_to admin_exports_path(user_id: user.id),
                           alert: "A reason is required to export account evidence."
      end

      if reason.length > DataExport::MAX_REASON
        return redirect_to admin_exports_path(user_id: user.id),
                           alert: "A reason is limited to #{DataExport::MAX_REASON} characters."
      end

      posts = user.tweets.order(:id).limit(MAX_POSTS + 1).to_a
      truncated = posts.size > MAX_POSTS
      posts = posts.first(MAX_POSTS)
      log = account_log(user)
      enforcement = log.select { |entry| ENFORCEMENT_ACTIONS.include?(entry.action) }
      warnings = user.user_warnings.includes(:actor).order(:created_at).to_a
      reversals = user.moderation_reversals.includes(:actor, :imposed_by).order(:created_at).to_a
      appeals = user.appeals.order(:created_at).to_a

      record = DataExport.create!(
        user: user,
        actor: current_user,
        reason: reason,
        post_count: posts.size,
        enforcement_count: enforcement.size + warnings.size + reversals.size
      )

      audit!("exports.download", target: "user:#{user.id}",
             detail: "export ##{record.id}: #{record.summary} - #{reason}")

      send_data evidence_file(user: user, record: record, posts: posts,
                              log: log, enforcement: enforcement, warnings: warnings,
                              reversals: reversals, appeals: appeals, truncated: truncated),
                filename: "account-#{user.id}-#{Time.current.strftime('%Y%m%d%H%M%S')}.txt",
                type: "text/plain"
    end

    # Re-download an export from the history without re-recording it. The
    # disclosure is the same event, so the reason and the original counts are
    # reproduced from the row rather than asked for again and written a second
    # time - duplicating the entry would make the log count one disclosure as
    # two. The re-download is still audited, because it is another time the
    # material left the panel.
    def download
      return refuse unless can?("exports.run")

      record = DataExport.includes(:user).find_by(id: params[:id])
      return render_not_found if record.nil?

      user = User.includes(:role).find(record.user_id)
      posts = user.tweets.order(:id).limit(MAX_POSTS).to_a
      log = account_log(user)

      audit!("exports.redownload", target: "user:#{user.id}",
             detail: "re-downloaded export ##{record.id} (#{record.reason})")

      send_data evidence_file(user: user, record: record, posts: posts, log: log,
                              enforcement: log.select { |e| ENFORCEMENT_ACTIONS.include?(e.action) },
                              warnings: user.user_warnings.includes(:actor).order(:created_at).to_a,
                              reversals: user.moderation_reversals.includes(:actor, :imposed_by).order(:created_at).to_a,
                              appeals: user.appeals.order(:created_at).to_a, truncated: false),
                type: "text/plain",
                filename: "account-#{user.id}-export-#{record.id}.txt"
    end

    private

    def refuse
      redirect_to admin_root_path, alert: "You do not have the exports.run permission."
    end

    # Every audit entry naming the account, older first so the file reads as a
    # timeline. The read is bounded so one very old account cannot make the
    # export unbounded.
    def account_log(user)
      AuditLog.includes(:actor)
              .where(target: "user:#{user.id}")
              .order(:created_at, :id)
              .limit(MAX_AUDIT)
    end

    # The export file. Plain text with fixed section rules, because the reader
    # is a lawyer or a support agent, not a machine, and a format that survives
    # being pasted into a ticket matters more than one that survives a parser.
    def evidence_file(user:, record:, posts:, log:, enforcement:, warnings:, reversals:, appeals:, truncated:)
      generated = Time.current.utc.iso8601
      lines = []
      lines << "ACCOUNT EVIDENCE EXPORT"
      lines << "=" * 72
      lines << "export:    ##{record.id}"
      lines << "account:   @#{user.username} (user ##{user.id})"
      lines << "generated: #{generated}"
      lines << "operator:  @#{current_user.username} (user ##{current_user.id})"
      lines << "reason:    #{record.reason}"
      lines << "contents:  #{posts.size} post(s), #{enforcement.size} enforcement entr(ies),"
      lines << "           #{warnings.size} warning(s), #{reversals.size} reversal(s), #{appeals.size} appeal(s)"
      lines << "NOTE: This file contains the account's posts and enforcement history."
      lines << "      It is a disclosure of personal data. Store and share it accordingly."

      lines << ""
      lines << "1. ACCOUNT RECORD"
      lines << "-" * 72
      account_record(user).each { |key, value| lines << format("%-18s %s", "#{key}:", value) }

      lines << ""
      lines << "2. POSTS"
      lines << "-" * 72
      if posts.empty?
        lines << "(no posts)"
      else
        posts.each do |tweet|
          lines << "post ##{tweet.id} - #{tweet.created_at.utc.iso8601} - #{tweet_state(tweet)}"
          lines << "  likes #{tweet.like_count}  retweets #{tweet.retweet_count}  replies #{tweet.reply_count}"
          lines << "  #{tweet.body.to_s.gsub("\n", ' ')}"
          lines << ""
        end
        lines << "(truncated at #{MAX_POSTS} posts)" if truncated
      end

      lines << ""
      lines << "3. ENFORCEMENT HISTORY"
      lines << "-" * 72
      lines << "(sanctions and decisions, oldest first)"
      if enforcement.empty?
        lines << "(no enforcement recorded)"
      else
        enforcement.each do |entry|
          lines << "#{entry.created_at.utc.iso8601}  #{entry.action}  by @#{entry.actor&.username || 'system'}"
          lines << "  #{entry.detail}"
        end
      end

      unless warnings.empty?
        lines << ""
        lines << "WARNINGS"
        warnings.each do |warning|
          lines << "warning ##{warning.id} - #{warning.created_at.utc.iso8601} - #{warning.category_label} - " \
                   "by @#{warning.actor&.username || 'system'}"
          lines << "  state: #{warning_state(warning)}"
          lines << "  #{warning.reason}"
        end
      end

      unless reversals.empty?
        lines << ""
        lines << "REVERSALS"
        reversals.each do |reversal|
          lines << "reversal ##{reversal.id} - #{reversal.created_at.utc.iso8601} - #{reversal.source_label} - " \
                   "by @#{reversal.actor&.username || 'system'}"
          lines << "  overturned: #{reversal.imposed_by ? "@#{reversal.imposed_by.username}" : 'unknown'}"
          lines << "  #{reversal.reason}"
        end
      end

      unless appeals.empty?
        lines << ""
        lines << "APPEALS"
        appeals.each do |appeal|
          lines << "appeal ##{appeal.id} - #{appeal.sanction_label} - #{appeal.state}"
          lines << "  #{appeal.body.to_s.gsub("\n", ' ')}"
        end
      end

      lines << ""
      lines << "4. FULL AUDIT TRAIL FOR THIS ACCOUNT"
      lines << "-" * 72
      if log.empty?
        lines << "(no entries)"
      else
        log.each do |entry|
          lines << "#{entry.created_at.utc.iso8601}  #{entry.action}  by @#{entry.actor&.username || 'system'}  #{entry.detail}"
        end
      end

      # A trailing newline so the file ends cleanly when concatenated into a
      # disclosure bundle.
      lines << ""
      lines.join("\n")
    end

    def account_record(user)
      {
        "id" => user.id,
        "username" => "@#{user.username}",
        "display_name" => user.display_name,
        "email" => user.email,
        "role" => user.role.name,
        "joined_at" => user.created_at.utc.iso8601,
        "last_login_at" => user.last_login_at&.utc&.iso8601 || "never",
        "status" => account_state(user),
        "verified" => user.is_verified?,
        "followers" => user.follower_count,
        "posts" => user.tweet_count,
        "bio" => user.bio.presence || "(none)",
        "location" => user.location.presence || "(none)",
        "website" => user.website.presence || "(none)",
        "account_flags" => user.account_tags.presence&.join(", ") || "(none)",
        "ban_reason" => user.ban_reason.presence || "(none)",
        "ban_expires_at" => user.ban_expires_at&.utc&.iso8601 || "(none)"
      }
    end

    def account_state(user)
      return "banned (permanent)" if user.is_banned && user.ban_permanent
      return "banned (temporary)" if user.is_banned
      return "suspended" if user.is_suspended

      "active"
    end

    def tweet_state(tweet)
      state = []
      state << "deleted" if tweet.is_deleted?
      state << "reply" if tweet.parent_id.present?
      state << "retweet of ##{tweet.retweet_of_id}" if tweet.retweet_of_id.present?
      state << "quote of ##{tweet.quote_of_id}" if tweet.quote_of_id.present?
      state << "pinned" if tweet.is_pinned?
      state.presence&.join(", ") || "original"
    end

    def warning_state(warning)
      return "expired" if warning.expired?
      return "acknowledged" if warning.acknowledged_at.present?

      "active"
    end
  end
end
