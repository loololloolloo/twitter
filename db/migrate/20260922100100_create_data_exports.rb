class CreateDataExports < ActiveRecord::Migration[8.1]
  # A per-account evidence export is a disclosure: it hands out the account
  # record, its posts and the enforcement history against it, which is exactly
  # the material a legal hold or a data-subject request asks for. Keeping a row
  # per export, rather than only hashing the event into the audit trail, means
  # the obligation can be answered later - who pulled what, when, and why - and
  # that the reason survives even if the audit trail is cleared.
  def change
    create_table :data_exports do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :actor_id
      t.string :reason, null: false, default: ""
      t.integer :post_count, null: false, default: 0
      t.integer :enforcement_count, null: false, default: 0

      t.timestamps
    end

    add_index :data_exports, :actor_id
  end
end
