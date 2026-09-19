class CreateStaffNotes < ActiveRecord::Migration[8.1]
  # Internal notes on an account. The panel already carries `users.tag_note`,
  # but that is a single free-text field that travels with the visibility
  # toggles: saving it means saving the tags, and a second operator overwrites
  # the first. Staff need to append observations to an account over time and
  # have each one attributed and dated, so they get their own rows.
  #
  # Nothing here is member-visible. A note is read only in the admin panel, so
  # it is deliberately not a notification and carries no state the account can
  # see or change.
  def change
    create_table :staff_notes do |t|
      t.integer :user_id, null: false
      t.integer :author_id
      t.text :body, null: false, default: ""
      t.boolean :pinned, null: false, default: false

      t.timestamps
    end

    add_index :staff_notes, :user_id
    add_index :staff_notes, [ :user_id, :created_at ]
  end
end
