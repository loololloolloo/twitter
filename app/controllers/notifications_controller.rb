class NotificationsController < ApplicationController
  def index
    require_login! || return

    @items = current_user.notifications.includes(:actor, :tweet).recent.limit(200)

    # Opening the list marks everything read, matching the classic client
    # where the badge cleared once you looked at the tab.
    current_user.notifications.unread.update_all(is_read: true, updated_at: Time.current)
  end
end