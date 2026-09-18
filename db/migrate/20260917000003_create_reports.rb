class CreateReports < ActiveRecord::Migration[8.1]
  # The moderation queue. A report names the account it is about, the reporter
  # (nil when the site itself raised it, for example a repeated-flag sweep) and
  # optionally the tweet it concerns, so the queue can show the offending post
  # inline instead of making the operator go looking for it.
  def change
    create_table :reports do |t|
      t.references :user, null: false, foreign_key: true
      t.references :reporter, null: true, foreign_key: { to_table: :users }
      t.references :tweet, null: true, foreign_key: true
      t.string :category, null: false, default: "abuse"
      t.text :detail, null: false, default: ""
      t.string :state, null: false, default: "open"
      t.text :resolution_note, null: false, default: ""
      t.integer :resolved_by_id
      t.datetime :resolved_at

      t.timestamps
    end

    add_index :reports, :state
    add_index :reports, [ :state, :created_at ]
  end
end
