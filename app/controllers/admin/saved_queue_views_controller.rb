# Saved queue views on the report queue.
#
# Operators work the same slices repeatedly - the open abuse reports, the
# week-old spam - and rebuilding that filter on every shift is the wasted time
# this removes. A view is the filter, stored under a name.
#
# Views are personal: every write here is scoped to the signed-in operator's own
# rows, so one operator cannot rename, delete or repoint another's shortcut.
class Admin::SavedQueueViewsController < AdminController
  before_action :require_views_permission
  before_action :load_own_view, only: [ :default, :destroy ]

  def create
    view = SavedQueueView.new(
      owner: current_user,
      queue: queue,
      name: params[:name].to_s.strip,
      state: filter_value(:state),
      category: filter_value(:category),
      sort: filter_value(:sort)
    )

    if view.save
      view.make_default! if params[:is_default].to_s == "1"
      audit!("queue_views.create", target: "queue_view:#{view.id}",
                                   detail: "#{view.name} on #{queue} - #{view.summary}")
      redirect_to queue_path, notice: "Saved view \"#{view.name}\"."
    else
      redirect_to queue_path, alert: view.errors.full_messages.to_sentence
    end
  end

  def default
    @view.make_default!
    audit!("queue_views.default", target: "queue_view:#{@view.id}",
                                  detail: "#{@view.name} is now the default #{queue} view")
    redirect_to queue_path, notice: "\"#{@view.name}\" is now your default view."
  end

  def destroy
    name = @view.name
    @view.destroy!
    audit!("queue_views.destroy", target: "queue_view:#{params[:id]}",
                                  detail: "deleted saved view #{name} on #{queue}")
    redirect_to queue_path, notice: "Deleted saved view \"#{name}\"."
  end

  private

  def require_views_permission
    require_permission!("reports.views")
  end

  # The queue this controller works. Only reports is wired, but reading it from
  # the request keeps the controller from hard-coding the one queue it serves.
  def queue
    candidate = params[:queue].to_s
    SavedQueueView::QUEUES.key?(candidate) ? candidate : "reports"
  end

  # A filter is only kept when the queue itself recognises the value, so a
  # tampered submission cannot store a saved view that matches nothing.
  def filter_value(key)
    value = params[key].to_s.strip
    case key
    when :state then Report::STATES.include?(value) ? value : ""
    when :category then Report::CATEGORIES.key?(value) ? value : ""
    when :sort then %w[risk oldest].include?(value) ? value : ""
    end
  end

  def load_own_view
    @view = SavedQueueView.owned_by(current_user).for_queue(queue).find_by(id: params[:id])

    return if @view

    redirect_to queue_path, alert: "That saved view does not exist."
  end

  def queue_path
    admin_reports_path
  end
end
