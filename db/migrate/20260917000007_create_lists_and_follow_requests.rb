class CreateListsAndFollowRequests < ActiveRecord::Migration[8.1]
  # Lists are curated timelines: an account groups other accounts and reads
  # their posts without following them. Membership is its own join table so an
  # account can be in many lists and a list can hold many accounts.
  #
  # Follow requests exist for protected accounts. A follow of a protected
  # account does not create a follow; it creates a pending request the account
  # has to approve, which is the behaviour the 2019 client had.
  def change
    create_table :lists do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false, default: ""
      t.text :description, null: false, default: ""
      t.boolean :is_private, null: false, default: false

      t.timestamps
    end

    add_index :lists, [ :user_id, :name ], unique: true

    create_table :list_memberships do |t|
      t.references :list, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end

    add_index :list_memberships, [ :list_id, :user_id ], unique: true

    create_table :follow_requests do |t|
      t.references :requester, null: false, foreign_key: { to_table: :users }
      t.references :target, null: false, foreign_key: { to_table: :users }
      t.string :state, null: false, default: "pending"

      t.timestamps
    end

    add_index :follow_requests, [ :requester_id, :target_id ], unique: true
    add_index :follow_requests, [ :target_id, :state ]
  end
end