# Approving or rejecting asks to follow a protected account.
#
# Only the target of a request can act on it, so every action loads the request
# through `current_user.received_follow_requests`. A request aimed at somebody
# else is a 404 rather than a forbidden, so a probe learns nothing about who has
# asked to follow whom.
class FollowRequestsController < ApplicationController
  before_action :require_login!

  def index
    @pending = current_user.received_follow_requests.pending
                             .includes(:requester)
                             .recent
  end

  def approve
    request = load_request
    return if performed?

    request.approve!
    audit!("follow_request.approve", target: "user:#{request.requester_id}",
                                     detail: "approved @#{request.requester.username}")
    redirect_to follow_requests_path, notice: "@#{request.requester.username} now follows you."
  end

  def reject
    request = load_request
    return if performed?

    request.reject!
    audit!("follow_request.reject", target: "user:#{request.requester_id}",
                                    detail: "declined @#{request.requester.username}")
    redirect_to follow_requests_path, notice: "Request from @#{request.requester.username} was declined."
  end

  private

  def load_request
    request = current_user.received_follow_requests.find_by(id: params[:id])
    render_not_found if request.nil?
    request
  end
end