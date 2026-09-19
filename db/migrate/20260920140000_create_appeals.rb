class CreateAppeals < ActiveRecord::Migration[8.1]
  # A member's contest of a ban or suspension, and the operator's decision on
  # it. It is a second-level workstream: deciding an appeal re-opens a decision
  # someone else already took, so the row keeps the sanctioning operator and
  # the deciding operator as separate columns. That is what lets the panel
  # refuse to let one person do both, and it is a fact about the appeal, not
  # something that can be recovered from the audit trail after the fact.
  #
  # There are no foreign keys on the operator columns, following staff_notes:
  # an operator may be deleted and the appeal should still read as history.
  def change
    create_table :appeals do |t|
      t.integer :user_id, null: false
      # The sanction being contested: "ban" or "suspension".
      t.string :sanction_kind, null: false, default: "ban"
      # Snapshots of the sanction at the moment the appeal was filed. The ban
      # fields on users are mutable, so reading them later would show the
      # appeal against a decision that had since changed or been lifted.
      t.string :sanction_reason, null: false, default: ""
      t.integer :sanction_actor_id
      t.text :body, null: false, default: ""

      t.string :state, null: false, default: "pending"
      t.integer :decided_by_id
      t.text :decision_note, null: false, default: ""
      t.datetime :decided_at

      t.timestamps
    end

    add_index :appeals, :user_id
    add_index :appeals, :state
    add_index :appeals, [ :state, :created_at ]
  end
end