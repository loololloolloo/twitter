class CreateSavedQueueViews < ActiveRecord::Migration[8.1]
  # A named filter on the report queue. Operators work the same slices
  # repeatedly - the open abuse reports, the week-old spam - and rebuilding that
  # filter on every shift is the wasted time the view removes. A view stores the
  # filter values only; the rows it matches are computed on read, so a view
  # never goes stale against the queue it points at.
  def change
    create_table :saved_queue_views do |t|
      t.string :name, null: false
      # The queue this view belongs to, so the same mechanism can be reused for
      # another workstream later without a second table.
      t.string :queue, null: false, default: "reports"
      # The filter values. Each is optional and empty means "any"; the column
      # names match the queue's own query parameters so a view round-trips
      # without a translation layer that could drift.
      t.string :state, null: false, default: ""
      t.string :category, null: false, default: ""
      t.string :sort, null: false, default: ""
      # The default is per-operator, not per-role: it is a personal starting
      # point, not a shared setting, so two operators do not fight over it.
      t.boolean :is_default, null: false, default: false
      t.integer :owner_id, null: false

      t.timestamps
    end

    # A view is private to the operator who saved it. Uniqueness is scoped to
    # the owner so two operators may both have a view called "Abuse".
    add_index :saved_queue_views, [ :owner_id, :queue, :name ], unique: true,
              name: "index_saved_queue_views_on_owner_queue_name"
    add_index :saved_queue_views, :queue
  end
end
