# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_16_000010) do
  create_table "audit_logs", force: :cascade do |t|
    t.string "action", null: false
    t.integer "actor_id"
    t.datetime "created_at", null: false
    t.text "detail", default: "", null: false
    t.string "target", default: "", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_audit_logs_on_actor_id"
  end

  create_table "dm_conversations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_a_id", null: false
    t.integer "user_b_id", null: false
    t.index ["user_a_id", "user_b_id"], name: "index_dm_conversations_on_user_a_id_and_user_b_id", unique: true
    t.index ["user_a_id"], name: "index_dm_conversations_on_user_a_id"
    t.index ["user_b_id"], name: "index_dm_conversations_on_user_b_id"
  end

  create_table "dm_messages", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.integer "dm_conversation_id", null: false
    t.integer "sender_id", null: false
    t.datetime "updated_at", null: false
    t.index ["dm_conversation_id", "created_at"], name: "index_dm_messages_on_dm_conversation_id_and_created_at"
    t.index ["dm_conversation_id"], name: "index_dm_messages_on_dm_conversation_id"
    t.index ["sender_id"], name: "index_dm_messages_on_sender_id"
  end

  create_table "follows", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "followee_id", null: false
    t.integer "follower_id", null: false
    t.datetime "updated_at", null: false
    t.index ["followee_id"], name: "index_follows_on_followee_id"
    t.index ["follower_id", "followee_id"], name: "index_follows_on_follower_id_and_followee_id", unique: true
    t.index ["follower_id"], name: "index_follows_on_follower_id"
  end

  create_table "likes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "kind", default: "like", null: false
    t.integer "tweet_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["tweet_id"], name: "index_likes_on_tweet_id"
    t.index ["user_id", "tweet_id", "kind"], name: "index_likes_on_user_id_and_tweet_id_and_kind", unique: true
    t.index ["user_id"], name: "index_likes_on_user_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.integer "actor_id"
    t.text "body", default: "", null: false
    t.datetime "created_at", null: false
    t.boolean "is_read", default: false, null: false
    t.string "kind", null: false
    t.integer "tweet_id"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["actor_id"], name: "index_notifications_on_actor_id"
    t.index ["tweet_id"], name: "index_notifications_on_tweet_id"
    t.index ["user_id", "created_at"], name: "index_notifications_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "permissions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.string "label", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_permissions_on_key", unique: true
  end

  create_table "profile_views", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "user_id", null: false
    t.integer "viewer_id", null: false
    t.index ["user_id", "created_at"], name: "index_profile_views_on_user_id_and_created_at"
    t.index ["viewer_id", "user_id"], name: "index_profile_views_on_viewer_id_and_user_id"
  end

  create_table "role_permissions", force: :cascade do |t|
    t.integer "permission_id", null: false
    t.integer "role_id", null: false
    t.index ["permission_id"], name: "index_role_permissions_on_permission_id"
    t.index ["role_id", "permission_id"], name: "index_role_permissions_on_role_id_and_permission_id", unique: true
    t.index ["role_id"], name: "index_role_permissions_on_role_id"
  end

  create_table "roles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "description"
    t.string "name", null: false
    t.integer "rank", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_roles_on_name", unique: true
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["token"], name: "index_sessions_on_token", unique: true
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "site_settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.text "value", default: "", null: false
    t.index ["key"], name: "index_site_settings_on_key", unique: true
  end

  create_table "tweet_views", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "dwell_seconds", default: 0, null: false
    t.integer "tweet_id", null: false
    t.integer "user_id", null: false
    t.index ["tweet_id", "user_id"], name: "index_tweet_views_on_tweet_id_and_user_id", unique: true
    t.index ["user_id", "created_at"], name: "index_tweet_views_on_user_id_and_created_at"
  end

  create_table "tweets", force: :cascade do |t|
    t.text "body", default: "", null: false
    t.datetime "created_at", null: false
    t.boolean "is_deleted", default: false, null: false
    t.boolean "is_pinned", default: false, null: false
    t.string "media_path"
    t.integer "parent_id"
    t.integer "retweet_of_id"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["created_at"], name: "index_tweets_on_created_at"
    t.index ["parent_id"], name: "index_tweets_on_parent_id"
    t.index ["retweet_of_id"], name: "index_tweets_on_retweet_of_id"
    t.index ["user_id", "created_at"], name: "index_tweets_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_tweets_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.integer "actions_performed", default: 0, null: false
    t.string "avatar_path"
    t.datetime "ban_expires_at"
    t.boolean "ban_permanent", default: false, null: false
    t.text "ban_reason", default: "", null: false
    t.string "banner_path"
    t.text "bio", default: "", null: false
    t.integer "bonus_followers", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "display_name", null: false
    t.string "email", null: false
    t.boolean "is_banned", default: false, null: false
    t.boolean "is_bot", default: false, null: false
    t.boolean "is_suspended", default: false, null: false
    t.boolean "is_verified", default: false, null: false
    t.datetime "last_action_at"
    t.datetime "last_login_at"
    t.string "location", default: "", null: false
    t.text "mind", default: "{}", null: false
    t.datetime "next_action_at"
    t.string "password_hash", null: false
    t.text "persona", default: "{}", null: false
    t.integer "role_id", null: false
    t.string "theme", default: "light", null: false
    t.datetime "updated_at", null: false
    t.string "username", null: false
    t.string "website", default: "", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["is_bot", "next_action_at"], name: "index_users_on_is_bot_and_next_action_at"
    t.index ["next_action_at"], name: "index_users_on_next_action_at"
    t.index ["role_id"], name: "index_users_on_role_id"
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  add_foreign_key "audit_logs", "users", column: "actor_id"
  add_foreign_key "dm_conversations", "users", column: "user_a_id"
  add_foreign_key "dm_conversations", "users", column: "user_b_id"
  add_foreign_key "dm_messages", "dm_conversations"
  add_foreign_key "dm_messages", "users", column: "sender_id"
  add_foreign_key "follows", "users", column: "followee_id"
  add_foreign_key "follows", "users", column: "follower_id"
  add_foreign_key "likes", "tweets"
  add_foreign_key "likes", "users"
  add_foreign_key "notifications", "tweets"
  add_foreign_key "notifications", "users"
  add_foreign_key "notifications", "users", column: "actor_id"
  add_foreign_key "profile_views", "users"
  add_foreign_key "profile_views", "users", column: "viewer_id"
  add_foreign_key "role_permissions", "permissions"
  add_foreign_key "role_permissions", "roles"
  add_foreign_key "sessions", "users"
  add_foreign_key "tweet_views", "tweets"
  add_foreign_key "tweet_views", "users"
  add_foreign_key "tweets", "tweets", column: "parent_id"
  add_foreign_key "tweets", "tweets", column: "retweet_of_id"
  add_foreign_key "tweets", "users"
  add_foreign_key "users", "roles"
end
