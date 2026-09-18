class CreateBlocksAndMutes < ActiveRecord::Migration[8.1]
  # Blocks and mutes are the two ways the client let an account silence another.
  #
  # A block is mutual and visible in effect: neither account sees the other, and
  # a block removes any follow between them. A mute is one-way and private: the
  # muting account stops seeing the muted one, and the muted account is never
  # told and can still follow.
  #
  # They are separate tables rather than one with a `kind` because their
  # semantics differ in both directions, and a query that means "am I blocked by
  # this person" has to read the opposite column from "have I blocked them".
  def change
    create_table :blocks do |t|
      t.references :blocker, null: false, foreign_key: { to_table: :users }
      t.references :blocked, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :blocks, [ :blocker_id, :blocked_id ], unique: true

    create_table :mutes do |t|
      t.references :muter, null: false, foreign_key: { to_table: :users }
      t.references :muted, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :mutes, [ :muter_id, :muted_id ], unique: true
  end
end