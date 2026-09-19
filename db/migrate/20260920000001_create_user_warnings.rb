class CreateUserWarnings < ActiveRecord::Migration[8.1]
  # A warning is the one moderation action that had nowhere to live. Bans,
  # suspensions, role changes and tags all write a column or a row; a warning
  # only wrote an audit entry, so an account's warnings could not be read back
  # or counted, and a second warning of the same kind could not expire on its
  # own. This gives them a record with a reason, an issuer and an optional
  # expiry, which is what the moderation history on the user page reads.
  def change
    create_table :user_warnings do |t|
      t.integer :user_id, null: false
      t.integer :actor_id
      t.string :category, null: false, default: "other"
      t.text :reason, null: false, default: ""
      t.datetime :expires_at
      t.datetime :acknowledged_at

      t.timestamps
    end

    add_index :user_warnings, :user_id
    add_index :user_warnings, [ :user_id, :created_at ]
  end
end
