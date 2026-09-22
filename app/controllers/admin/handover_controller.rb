module Admin
  # The shift handover digest. This is the screen an operator reads when they
  # sit down: what is open across the queues, what changed recently, and which
  # items cannot be closed by the person who touched them last.
  #
  # It reads and writes nothing, so it is a GET with no confirmation. The point
  # is that it is resident rather than something an operator assembles by
  # opening six tabs at the start of every shift.
  class HandoverController < AdminController
    # How far back "recently" reaches. A shift is bounded, so six hours is the
    # window that answers "what happened while I was away" without turning the
    # screen into the full audit log.
    RECENT_WINDOW = 6.hours

    def show
      require_permission!("handover.view")

      @generated_at = Time.current
      @window_start = @generated_at - RECENT_WINDOW

      @open = open_counts
      @recent = recent_actions
      @needs_attention = items_needing_attention
      @newest = newest_accounts
    end

    private

    # What is waiting, one entry per queue. Only the queues the viewer holds the
    # permission for are counted: a handover that names a figure for a queue its
    # reader cannot open is noise, and worse, it leaks the existence of work
    # behind a permission they were not granted. Each entry carries the path to
    # the queue so the digest is the entry point to the work, not a dead report.
    def open_counts
      items = []

      if can?("reports.view")
        items << count_row("Open reports", Report.open.count, admin_reports_path(state: "open"))
      end

      if can?("cases.view")
        items << count_row("Open cases", ModerationCase.open.count, admin_cases_path(state: "open"))
      end

      if can?("appeals.view")
        items << count_row("Pending appeals", Appeal.pending.count, admin_appeals_path(state: "pending"))
      end

      if can?("verification.view")
        items << count_row("Verification requests",
                           VerificationRequest.pending.count,
                           admin_verification_path(state: "pending"))
      end

      if can?("approvals.decide")
        items << count_row("Four-eyes approvals", ApprovalRequest.pending.count,
                           admin_approvals_path(state: "pending"))
      end

      if can?("escalations.view")
        items << count_row("Escalation flags", User.where(requires_review: true).count,
                           admin_escalations_path(tab: "review"))
      end

      items
    end

    def count_row(label, count, path)
      { label: label, count: count, path: path }
    end

    # What the last shift did to the site. The audit log is the record of that,
    # filtered to the window and trimmed to the actions an operator would relay
    # to the next one - enforcement, decisions and permission changes - rather
    # than every read-only maintenance entry.
    HANDOVER_ACTIONS = %w[
      users.ban users.suspend users.reverse users.warn users.verify
      users.delete users.email users.handle users.roles users.tags users.permissions
      appeals.decide verification.decide approvals.apply approvals.decide cases.decide
      reports.resolve settings.blocked_terms
    ].freeze

    QUERY_LIMIT = 100

    def recent_actions
      return [] unless can?("audit.view")

      AuditLog.includes(:actor)
              .where(created_at: @window_start..)
              .where(action: HANDOVER_ACTIONS)
              .order(created_at: :desc, id: :desc)
              .limit(QUERY_LIMIT)
    end

    # The work that cannot be closed by whichever operator touched it last.
    # These are the separation-of-duties queues: an appeal whose sanction was
    # imposed by the operator reading the screen, a case they opened, a
    # four-eyes request they filed, a verification request on their own
    # account. Surfacing them is the point of the digest - an item that has sat
    # pending because its only available owner is barred looks identical to one
    # nobody has reached yet, unless it is called out.
    def items_needing_attention
      items = []

      if can?("appeals.view")
        Appeal.pending.includes(:user, :sanction_actor).each do |appeal|
          next unless appeal.barred_for?(current_user)

          items << attention_row(
            kind: "Appeal",
            subject: "@#{appeal.user.username}",
            detail: appeal.bar_reason(current_user),
            path: admin_appeals_path(state: "pending")
          )
        end
      end

      if can?("cases.view")
        ModerationCase.open.includes(:user, :tweet).each do |moderation_case|
          next unless moderation_case.barred_for?(current_user)

          items << attention_row(
            kind: "Case",
            subject: moderation_case.subject_label,
            detail: moderation_case.bar_reason(current_user),
            path: admin_case_path(moderation_case)
          )
        end
      end

      if can?("approvals.decide")
        ApprovalRequest.pending.includes(:user).each do |request|
          next unless request.barred_for?(current_user)

          items << attention_row(
            kind: "Approval",
            subject: "@#{request.user.username}",
            detail: request.bar_reason(current_user),
            path: admin_approvals_path(state: "pending")
          )
        end
      end

      if can?("verification.view")
        VerificationRequest.pending.includes(:user).each do |request|
          next unless request.barred_for?(current_user)

          items << attention_row(
            kind: "Verification",
            subject: "@#{request.user.username}",
            detail: request.bar_reason(current_user),
            path: admin_verification_path(state: "pending")
          )
        end
      end

      items
    end

    def attention_row(kind:, subject:, detail:, path:)
      { kind: kind, subject: subject, detail: detail, path: path }
    end

    # The accounts to look at first on the next shift. New signups are checked
    # briefly at handover because the spam and impersonation accounts announce
    # themselves in their first hours.
    def newest_accounts
      return [] unless can?("users.view")

      User.includes(:role).order(created_at: :desc, id: :desc).limit(8)
    end
  end
end
