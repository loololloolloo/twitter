class CreateContent < ActiveRecord::Migration[8.1]
  def change
    create_table :tweets do |t|
      t.references :user, null: false, foreign_key: true
      t.text    :body, null: false, default: ""
      t.references :parent, foreign_key: { to_table: :tweets }
      t.references :retweet_of, foreign_key: { to_table: :tweets }
      t.string  :media_path
      t.boolean :is_deleted, null: false, default: false
      t.boolean :is_pinned, null: false, default: false
      t.timestamps
    end
    add_index :tweets, [ :user_id, :created_at ]

    create_table :likes do |t|
      t.references :user, null: false, foreign_key: true
      t.references :tweet, null: false, foreign_key: true
      t.timestamps
    end
    add_index :likes, [ :user_id, :tweet_id ], unique: true

    create_table :follows do |t|
      t.references :follower, null: false, foreign_key: { to_table: :users }
      t.references :followee, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :follows, [ :follower_id, :followee_id ], unique: true

    create_table :dm_conversations do |t|
      t.references :user_a, null: false, foreign_key: { to_table: :users }
      t.references :user_b, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :dm_conversations, [ :user_a_id, :user_b_id ], unique: true

    create_table :dm_messages do |t|
      t.references :dm_conversation, null: false, foreign_key: true
      t.references :sender, null: false, foreign_key: { to_table: :users }
      t.text :body, null: false
      t.timestamps
    end

    create_table :notifications do |t|
      t.references :user, null: false, foreign_key: true
      t.references :actor, foreign_key: { to_table: :users }
      t.string :kind, null: false
      t.references :tweet, foreign_key: true
      t.text   :body, null: false, default: ""
      t.boolean :is_read, null: false, default: false
      t.timestamps
    end
    add_index :notifications, [ :user_id, :created_at ]
  end
end