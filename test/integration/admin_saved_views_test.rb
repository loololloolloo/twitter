require "test_helper"

# Saved queue views let an operator name the slice of the queue they work
# repeatedly instead of rebuilding the filter each shift. These tests cover the
# three things that make the feature trustworthy: a view is personal to its
# owner, the filter it stores is the queue's own filter (so it cannot drift or
# be tampered into something that matches nothing), and a saved default opens
# the queue without ever overriding a filter the operator set explicitly.
class AdminSavedViewsTest < ActionDispatch::IntegrationTest
  test "an operator saves the current filter and reopens the queue through it" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "spammy")
    Report.create!(user: target, category: "spam", detail: "advertising")

    sign_in(owner)
    assert_difference "SavedQueueView.count", 1 do
      post admin_queue_views_path, params: { queue: "reports", name: "Open spam",
                                             state: "open", category: "spam", sort: "risk" }
    end

    view = SavedQueueView.last
    assert_equal owner.id, view.owner_id
    assert_equal "reports", view.queue
    assert_equal "open", view.state
    assert_equal "spam", view.category
    assert_equal "risk", view.sort

    # Applying it is a read: the queue renders through the stored filter.
    get admin_reports_path(SavedQueueView.filter_params(view))
    assert_response :success
    assert_match(/Open spam/, response.body)
    assert_match(/@spammy/, response.body)
  end

  test "a view stores only filters the queue recognises" do
    owner = create_user(username: "king", role: "owner")
    sign_in(owner)

    post admin_queue_views_path, params: { queue: "reports", name: "Bogus",
                                           state: "everything", category: "nonsense",
                                           sort: "alphabetical" }

    view = SavedQueueView.last
    assert_equal "", view.state
    assert_equal "", view.category
    assert_equal "", view.sort
    assert_match(/no filters/, view.summary)
  end

  test "setting a new default clears the operator's previous one" do
    owner = create_user(username: "king", role: "owner")
    sign_in(owner)

    post admin_queue_views_path, params: { queue: "reports", name: "First", state: "open" }
    first = SavedQueueView.last
    post admin_queue_views_path, params: { queue: "reports", name: "Second", state: "dismissed" }
    second = SavedQueueView.last

    post admin_queue_view_default_path(first)
    assert first.reload.is_default

    post admin_queue_view_default_path(second)
    assert second.reload.is_default
    refute first.reload.is_default, "two defaults would leave the queue picking arbitrarily"
  end

  test "a saved default opens the queue on its filter but an explicit filter wins" do
    owner = create_user(username: "king", role: "owner")
    open_report = create_user(username: "open_one")
    closed_report = create_user(username: "closed_one")
    Report.create!(user: open_report, category: "spam")
    dismissed = Report.create!(user: closed_report, category: "spam")
    dismissed.update!(state: "dismissed")

    sign_in(owner)
    post admin_queue_views_path, params: { queue: "reports", name: "Dismissed",
                                           state: "dismissed" }
    view = SavedQueueView.last
    post admin_queue_view_default_path(view)

    # A bare request opens on the saved default.
    get admin_reports_path
    assert_response :success
    assert_match(/@closed_one/, response.body)

    # An explicit state tab is never overridden by the shortcut.
    get admin_reports_path(state: "open")
    assert_response :success
    assert_match(/@open_one/, response.body)
    refute_match(/@closed_one/, response.body)
  end

  test "an operator cannot delete another operator's view" do
    owner = create_user(username: "king", role: "owner")
    other = create_user(username: "other", role: "admin")
    sign_in(other)
    post admin_queue_views_path, params: { queue: "reports", name: "Mine", state: "open" }
    view = SavedQueueView.last

    sign_in(owner)
    assert_no_difference "SavedQueueView.count" do
      delete admin_queue_view_path(view)
    end
    assert_response :redirect
    assert SavedQueueView.exists?(view.id), "a view is private to the operator who saved it"
  end

  test "a role without reports.views can read the queue but not save a view" do
    member = create_user(username: "member", role: "user")
    sign_in(member)

    assert_no_difference "SavedQueueView.count" do
      post admin_queue_views_path, params: { queue: "reports", name: "Nope", state: "open" }
    end
    assert_response :redirect
  end

  test "creating and deleting a view are audited" do
    owner = create_user(username: "king", role: "owner")
    sign_in(owner)

    post admin_queue_views_path, params: { queue: "reports", name: "Audited", state: "open" }
    view = SavedQueueView.last
    assert AuditLog.exists?(action: "queue_views.create", actor_id: owner.id)

    delete admin_queue_view_path(view)

    entry = AuditLog.where(action: "queue_views.destroy", actor_id: owner.id).last
    assert entry, "deleting a shortcut still changes the queue an operator sees, so it is audited"
    assert_match(/Audited/, entry.detail)
  end
end
