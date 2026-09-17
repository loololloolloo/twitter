class AddTweetViewsAndProfiles < ActiveRecord::Migration[8.1]
  # Impressions recorded when a bot opens a tweet. Rows are the raw material
  # for view counts and for "what has this account already seen", which keeps
  # a bot from reading the same post twice in a row.
  create_table :tweet_views do |t|
    t.integer :tweet_id, null: false
    t.integer :user_id, null: false
    # How long the viewer lingered, in seconds. Bots vary this so the number
    # does not look like a constant.
    t.integer :dwell_seconds, null: false, default: 0
    t.datetime :created_at, null: false
  end

  add_index :tweet_views, [ :tweet_id, :user_id ], unique: true
  add_index :tweet_views, [ :user_id, :created_at ]
  add_foreign_key :tweet_views, :tweets
  add_foreign_key :tweet_views, :users

  # Profile opens. Twitter showed no public counter for these in 2015, but the
  # event is what makes a bot's session read as browsing rather than acting.
  create_table :profile_views do |t|
    t.integer :user_id, null: false
    t.integer :viewer_id, null: false
    t.datetime :created_at, null: false
  end

  add_index :profile_views, [ :user_id, :created_at ]
  add_index :profile_views, [ :viewer_id, :user_id ]
  add_foreign_key :profile_views, :users, column: :user_id
  add_foreign_key :profile_views, :users, column: :viewer_id
end