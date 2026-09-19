# A banned member's appeal. The ban gate keeps a suspended account out of
# every other endpoint, so this controller has to be reachable while banned -
# it is listed in `BAN_GATE_EXEMPT` for that reason. The member may only file
# an appeal about their own account; there is no id in the request to widen it.
class AppealsController < ApplicationController
  before_action :require_login!
  before_action :require_banned!

  def create
    kind = "ban"

    # One open appeal at a time. A second is not a new contest, it is the
    # member asking twice, and the queue should not grow rows for it.
    if current_user.appeals.pending.exists?
      return redirect_to banned_path, alert: "You already have an appeal awaiting a decision."
    end

    body = params[:body].to_s.strip
    if body.blank?
      return redirect_to banned_path, alert: "Tell us why the decision should be reviewed."
    end

    current_user.appeals.create!(
      sanction_kind: kind,
      sanction_reason: current_user.ban_reason.to_s,
      sanction_actor_id: sanction_actor_id_for(kind),
      body: body
    )

    audit!("appeals.create", target: "user:#{current_user.id}", detail: "filed a #{kind} appeal")

    redirect_to banned_path, notice: "Your appeal has been sent for review."
  end

  private

  # A ban carries no operator column on users, so the sanctioning operator is
  # read from the audit trail: the most recent ban on this account was the one
  # that put it here, and its actor is the person barred from the appeal.
  def sanction_actor_id_for(kind)
    entry = AuditLog.where(target: "user:#{current_user.id}", action: "users.ban")
                    .order(created_at: :desc, id: :desc)
                    .first
    return nil if entry.nil?

    entry.actor_id
  end

  def require_banned!
    return if current_user.is_banned? || current_user.is_suspended?

    redirect_to home_path
  end
end