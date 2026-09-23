class CreateListSubscriptions < ActiveRecord::Migration[8.1]
  # The 2019 list page header printed the follower count beside the member
  # count, because a list is followed the same way an account is: you read it
  # without following the accounts inside it. Membership answers who is on the
  # list; this table answers who reads it. They are independent, which is why a
  # separate row is needed rather than a column on the membership.
  def change
    create_table :list_subscriptions do |t|
      t.integer :list_id, null: false
      t.integer :user_id, null: false

      t.timestamps
    end

    add_index :list_subscriptions, [ :list_id, :user_id ], unique: true
    add_index :list_subscriptions, :list_id
    add_index :list_subscriptions, :user_id
  end
end
