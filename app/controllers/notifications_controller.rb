class NotificationsController < ApplicationController
  # The 2019 client split notifications into "All" and "Mentions". Both read the
  # same table; the Mentions tab is the subset whose kind is a mention, which is
  # why this is a filter rather than a second store.
  TABS = %w[all mentions].freeze

  def index
    require_login! || return

    @tab = params[:tab].presence_in(TABS) || "all"

    scope = current_user.notifications.includes(:actor, :tweet).recent

    # A muted or blocked account's notifications are dropped: the reader has
    # said they do not want to see that account, and an alert is still seeing it.
    silenced = current_user.silenced_account_ids
    scope = scope.where.not(actor_id: silenced) if silenced.any?

    scope = scope.where(kind: "mention") if @tab == "mentions"

    @items = scope.limit(200)

    # Opening the list marks everything read, matching the classic client
    # where the badge cleared once you looked at the tab.
    current_user.notifications.unread.update_all(is_read: true, updated_at: Time.current)
  end
end