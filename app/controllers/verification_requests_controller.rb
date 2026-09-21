# A member's request for the verified badge. The request only ever lands on
# the signed-in account, and it never grants the badge itself: an operator
# decides it on the admin verification queue, which is where the badge is
# actually granted. Keeping the two apart is the point - the member cannot
# verify themselves by asking.
class VerificationRequestsController < ApplicationController
  before_action :require_login!

  def create
    # One open request at a time. A second is the member asking twice, and the
    # queue should not grow rows for it.
    if current_user.verification_requests.pending.exists?
      return redirect_to settings_path, alert: "You already have a verification request in review."
    end

    if current_user.is_verified
      return redirect_to settings_path, alert: "Your account is already verified."
    end

    category = params[:category].to_s
    unless VerificationRequest::CATEGORIES.key?(category)
      return redirect_to settings_path, alert: "Choose what you are asking to be verified as."
    end

    body = params[:body].to_s.strip
    if body.blank?
      return redirect_to settings_path, alert: "Tell us why your account should carry the badge."
    end

    current_user.verification_requests.create!(category: category, body: body)

    redirect_to settings_path, notice: "Your verification request has been sent for review."
  end

  private

  def require_login!
    return if signed_in?

    redirect_to login_path
  end
end
