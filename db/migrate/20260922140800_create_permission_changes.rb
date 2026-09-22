class CreatePermissionChanges < ActiveRecord::Migration[8.1]
  # Role and permission edits are the most sensitive thing the panel does: every
  # other capability in the console rides on the grants made here. The audit
  # trail records that a change happened, but not what capability was gained or
  # lost, so it cannot answer "what could this role do before, and what can it
  # do now". This table keeps the before/after set for each edit so a reviewer
  # sees the capability diff rather than a count.
  #
  # The keys are stored as JSON arrays rather than joined into the audit detail
  # because they are read back as a set to subtract one side from the other.
  def change
    create_table :permission_changes do |t|
      t.integer :role_id, null: false
      # Nullable: a change made outside a request (a console, a future task)
      # has no acting operator, and the row should still record the edit.
      t.integer :actor_id
      t.text :before_keys, null: false, default: "[]"
      t.text :after_keys, null: false, default: "[]"
      # Why the edit was made. Optional, because the editor is a live form and
      # a missing note must not block a real change; the diff stands on its own.
      t.text :note, null: false, default: ""

      t.timestamps
    end

    add_index :permission_changes, :role_id
    add_index :permission_changes, :created_at
  end
end
