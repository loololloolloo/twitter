class CreateApprovalRequests < ActiveRecord::Migration[8.1]
  # Four-eyes approval for the actions with the widest blast radius. A single
  # operator who can permanently suspend an account or rewrite its sign-in
  # identifier is the 2020 failure mode in miniature, so those changes are
  # filed as a pending request and only take effect when a *different* operator
  # approves them.
  #
  # The operator columns carry no foreign keys, following appeals and cases: an
  # operator may be deleted and the record should still read as history. The
  # target account, though, is a real foreign key - a request about a deleted
  # account has nothing left to apply to.
  def change
    create_table :approval_requests do |t|
      t.references :user, null: false, foreign_key: true
      t.string :action_key, null: false, default: ""
      # The proposed change, as JSON. The registry in ApprovalRequest decides
      # what keys each action reads; storing it as text keeps a new action from
      # needing a migration.
      t.text :payload, null: false, default: "{}"

      t.integer :requested_by_id
      t.text :request_note, null: false, default: ""

      t.string :state, null: false, default: "pending"
      t.integer :decided_by_id
      t.text :decision_note, null: false, default: ""
      t.datetime :decided_at

      t.timestamps
    end

    add_index :approval_requests, :action_key
    add_index :approval_requests, :state
    add_index :approval_requests, [ :state, :created_at ]
  end
end
