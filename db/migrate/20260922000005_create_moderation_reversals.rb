class CreateModerationReversals < ActiveRecord::Migration[8.1]
  # A moderation action is reversible, but a silent delete of the row is not a
  # reversal - it is a cover-up. This table records the fact separately: the
  # original sanction stays exactly as it was, named by `action`/`source`, and
  # the reversal is appended next to it with the operator who made it and the
  # reason. The account's history then reads as "banned, then reversed",
  # which is the truth, rather than as "never banned at all".
  #
  # The pairing is deliberately loose. A reversal can undo a ban, a suspension
  # or a warning, so `source` names the kind and `source_id` the row where
  # there is one; a ban is stored on the user itself and has no separate row,
  # so it carries source_id 0. That is enough to line a reversal up with the
  # audit entry it explains without a foreign key to a table that varies.
  def change
    create_table :moderation_reversals do |t|
      t.integer :user_id, null: false
      t.integer :actor_id
      # The operator whose sanction is being undone. Stored because the rule
      # that the imposer cannot reverse their own action has to be checkable
      # from the reversal row alone, and because the history credits both
      # decisions.
      t.integer :imposed_by_id
      t.string :source, null: false, default: ""
      t.integer :source_id, null: false, default: 0
      t.string :action, null: false, default: ""
      t.text :reason, null: false, default: ""

      t.timestamps
    end

    add_index :moderation_reversals, [ :user_id, :created_at ]
    add_index :moderation_reversals, [ :source, :source_id ]
  end
end
