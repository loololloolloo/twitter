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

ActiveRecord::Schema[8.1].define(version: 2026_09_22_000002) do
  create_table "appeals", force: :cascade do |t|
    t.text "body", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "decided_at"
    t.integer "decided_by_id"
    t.text "decision_note", default: "", null: false
    t.integer "sanction_actor_id"
    t.string "sanction_kind", default: "ban", null: false
    t.string "sanction_reason", default: "", null: false
    t.string "state", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["state", "created_at"], name: "index_appeals_on_state_and_created_at"
    t.index ["state"], name: "index_appeals_on_state"
    t.index ["user_id"], name: "index_appeals_on_user_id"
  end

  create_table "approval_requests", force: :cascade do |t|
    t.string "action_key", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "decided_at"
    t.integer "decided_by_id"
    t.text "decision_note", default: "", null: false
    t.text "payload", default: "{}", null: false
    t.text "request_note", default: "", null: false
    t.integer "requested_by_id"
    t.string "state", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["action_key"], name: "index_approval_requests_on_action_key"
    t.index ["state", "created_at"], name: "index_approval_requests_on_state_and_created_at"
    t.index ["state"], name: "index_approval_requests_on_state"
    t.index ["user_id"], name: "index_approval_requests_on_user_id"
  end

  create_table "audit_logs", force: :cascade do |t|
    t.string "action", null: false
    t.integer "actor_id"
    t.datetime "created_at", null: false
    t.text "detail", default: "", null: false
    t.string "target", default: "", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_audit_logs_on_actor_id"
  end

  create_table "blocked_terms", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "category", default: "other", null: false
    t.datetime "created_at", null: false
    t.integer "created_by_id"
    t.string "mode", default: "flag", null: false
    t.text "note", default: "", null: false
    t.string "term", null: false
    t.datetime "updated_at", null: false
    t.index "LOWER(term)", name: "index_blocked_terms_on_lower_term", unique: true
    t.index ["active"], name: "index_blocked_terms_on_active"
  end

  create_table "blocks", force: :cascade do |t|
    t.integer "blocked_id", null: false
    t.integer "blocker_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["blocked_id"], name: "index_blocks_on_blocked_id"
    t.index ["blocker_id", "blocked_id"], name: "index_blocks_on_blocker_id_and_blocked_id", unique: true
    t.index ["blocker_id"], name: "index_blocks_on_blocker_id"
  end

  create_table "bookmarks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "tweet_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["tweet_id"], name: "index_bookmarks_on_tweet_id"
    t.index ["user_id", "created_at"], name: "index_bookmarks_on_user_id_and_created_at"
    t.index ["user_id", "tweet_id"], name: "index_bookmarks_on_user_id_and_tweet_id", unique: true
    t.index ["user_id"], name: "index_bookmarks_on_user_id"
  end

  create_table "case_links", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "linked_by_id"
    t.integer "moderation_case_id", null: false
    t.integer "report_id", null: false
    t.datetime "updated_at", null: false
    t.index ["moderation_case_id"], name: "index_case_links_on_moderation_case_id"
    t.index ["report_id"], name: "index_case_links_on_report_id", unique: true
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

  create_table "follow_requests", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "requester_id", null: false
    t.string "state", default: "pending", null: false
    t.integer "target_id", null: false
    t.datetime "updated_at", null: false
    t.index ["requester_id", "target_id"], name: "index_follow_requests_on_requester_id_and_target_id", unique: true
    t.index ["requester_id"], name: "index_follow_requests_on_requester_id"
    t.index ["target_id", "state"], name: "index_follow_requests_on_target_id_and_state"
    t.index ["target_id"], name: "index_follow_requests_on_target_id"
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

  create_table "list_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "list_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["list_id", "user_id"], name: "index_list_memberships_on_list_id_and_user_id", unique: true
    t.index ["list_id"], name: "index_list_memberships_on_list_id"
    t.index ["user_id"], name: "index_list_memberships_on_user_id"
  end

  create_table "lists", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description", default: "", null: false
    t.boolean "is_private", default: false, null: false
    t.string "name", default: "", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "name"], name: "index_lists_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_lists_on_user_id"
  end

  create_table "moderation_cases", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "decided_at"
    t.integer "decided_by_id"
    t.text "decision_note", default: "", null: false
    t.integer "opened_by_id"
    t.string "state", default: "open", null: false
    t.text "summary", default: "", null: false
    t.string "title", default: "", null: false
    t.integer "tweet_id"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["state", "created_at"], name: "index_moderation_cases_on_state_and_created_at"
    t.index ["state"], name: "index_moderation_cases_on_state"
    t.index ["tweet_id"], name: "index_moderation_cases_on_tweet_id"
    t.index ["user_id"], name: "index_moderation_cases_on_user_id"
  end

  create_table "mutes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "muted_id", null: false
    t.integer "muter_id", null: false
    t.datetime "updated_at", null: false
    t.index ["muted_id"], name: "index_mutes_on_muted_id"
    t.index ["muter_id", "muted_id"], name: "index_mutes_on_muter_id_and_muted_id", unique: true
    t.index ["muter_id"], name: "index_mutes_on_muter_id"
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

  create_table "poll_options", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "label", default: "", null: false
    t.integer "poll_id", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["poll_id", "position"], name: "index_poll_options_on_poll_id_and_position"
  end

  create_table "poll_votes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "poll_id", null: false
    t.integer "poll_option_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["poll_id", "user_id"], name: "index_poll_votes_on_poll_id_and_user_id", unique: true
    t.index ["poll_option_id"], name: "index_poll_votes_on_poll_option_id"
  end

  create_table "polls", force: :cascade do |t|
    t.datetime "closes_at"
    t.datetime "created_at", null: false
    t.integer "tweet_id", null: false
    t.datetime "updated_at", null: false
    t.index ["tweet_id"], name: "index_polls_on_tweet_id", unique: true
  end

  create_table "profile_views", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "user_id", null: false
    t.integer "viewer_id", null: false
    t.index ["user_id", "created_at"], name: "index_profile_views_on_user_id_and_created_at"
    t.index ["viewer_id", "user_id"], name: "index_profile_views_on_viewer_id_and_user_id"
  end

  create_table "reports", force: :cascade do |t|
    t.string "category", default: "abuse", null: false
    t.datetime "created_at", null: false
    t.text "detail", default: "", null: false
    t.integer "reporter_id"
    t.text "resolution_note", default: "", null: false
    t.datetime "resolved_at"
    t.integer "resolved_by_id"
    t.string "state", default: "open", null: false
    t.integer "tweet_id"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["reporter_id"], name: "index_reports_on_reporter_id"
    t.index ["state", "created_at"], name: "index_reports_on_state_and_created_at"
    t.index ["state"], name: "index_reports_on_state"
    t.index ["tweet_id"], name: "index_reports_on_tweet_id"
    t.index ["user_id"], name: "index_reports_on_user_id"
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

  create_table "staff_notes", force: :cascade do |t|
    t.integer "author_id"
    t.text "body", default: "", null: false
    t.datetime "created_at", null: false
    t.boolean "pinned", default: false, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "created_at"], name: "index_staff_notes_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_staff_notes_on_user_id"
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
    t.string "alt_text"
    t.text "body", default: "", null: false
    t.integer "bonus_favourites", default: 0, null: false
    t.integer "bonus_likes", default: 0, null: false
    t.integer "bonus_retweets", default: 0, null: false
    t.datetime "created_at", null: false
    t.boolean "is_deleted", default: false, null: false
    t.boolean "is_pinned", default: false, null: false
    t.string "media_path"
    t.string "media_url"
    t.integer "parent_id"
    t.datetime "pinned_at"
    t.integer "quote_of_id"
    t.datetime "reply_hidden_at"
    t.integer "retweet_of_id"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["created_at"], name: "index_tweets_on_created_at"
    t.index ["parent_id"], name: "index_tweets_on_parent_id"
    t.index ["quote_of_id"], name: "index_tweets_on_quote_of_id"
    t.index ["reply_hidden_at"], name: "index_tweets_on_reply_hidden_at"
    t.index ["retweet_of_id"], name: "index_tweets_on_retweet_of_id"
    t.index ["user_id", "created_at"], name: "index_tweets_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_tweets_on_user_id"
  end

  create_table "user_warnings", force: :cascade do |t|
    t.datetime "acknowledged_at"
    t.integer "actor_id"
    t.string "category", default: "other", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.text "reason", default: "", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "created_at"], name: "index_user_warnings_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_user_warnings_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "avatar_path"
    t.datetime "ban_expires_at"
    t.boolean "ban_permanent", default: false, null: false
    t.text "ban_reason", default: "", null: false
    t.string "banner_path"
    t.text "bio", default: "", null: false
    t.integer "bonus_followers", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "design", default: "2019", null: false
    t.string "display_name", null: false
    t.boolean "do_not_amplify", default: false, null: false
    t.string "email", null: false
    t.boolean "is_banned", default: false, null: false
    t.boolean "is_compromised", default: false, null: false
    t.boolean "is_high_profile", default: false, null: false
    t.boolean "is_suspended", default: false, null: false
    t.boolean "is_verified", default: false, null: false
    t.datetime "last_login_at"
    t.string "location", default: "", null: false
    t.string "password_hash", null: false
    t.boolean "protected", default: false, null: false
    t.boolean "requires_review", default: false, null: false
    t.integer "role_id", null: false
    t.boolean "search_blacklist", default: false, null: false
    t.text "tag_note", default: "", null: false
    t.string "theme", default: "light", null: false
    t.boolean "trends_blacklist", default: false, null: false
    t.datetime "updated_at", null: false
    t.string "username", null: false
    t.string "website", default: "", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["role_id"], name: "index_users_on_role_id"
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  create_table "verification_requests", force: :cascade do |t|
    t.text "body", default: "", null: false
    t.string "category", default: "other", null: false
    t.datetime "created_at", null: false
    t.datetime "decided_at"
    t.text "decision_note", default: "", null: false
    t.integer "reviewed_by_id"
    t.string "state", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["state", "created_at"], name: "index_verification_requests_on_state_and_created_at"
    t.index ["state"], name: "index_verification_requests_on_state"
    t.index ["user_id"], name: "index_verification_requests_on_user_id"
  end

  add_foreign_key "approval_requests", "users"
  add_foreign_key "audit_logs", "users", column: "actor_id"
  add_foreign_key "blocks", "users", column: "blocked_id"
  add_foreign_key "blocks", "users", column: "blocker_id"
  add_foreign_key "bookmarks", "tweets"
  add_foreign_key "bookmarks", "users"
  add_foreign_key "case_links", "moderation_cases"
  add_foreign_key "case_links", "reports"
  add_foreign_key "dm_conversations", "users", column: "user_a_id"
  add_foreign_key "dm_conversations", "users", column: "user_b_id"
  add_foreign_key "dm_messages", "dm_conversations"
  add_foreign_key "dm_messages", "users", column: "sender_id"
  add_foreign_key "follow_requests", "users", column: "requester_id"
  add_foreign_key "follow_requests", "users", column: "target_id"
  add_foreign_key "follows", "users", column: "followee_id"
  add_foreign_key "follows", "users", column: "follower_id"
  add_foreign_key "likes", "tweets"
  add_foreign_key "likes", "users"
  add_foreign_key "list_memberships", "lists"
  add_foreign_key "list_memberships", "users"
  add_foreign_key "lists", "users"
  add_foreign_key "mutes", "users", column: "muted_id"
  add_foreign_key "mutes", "users", column: "muter_id"
  add_foreign_key "notifications", "tweets"
  add_foreign_key "notifications", "users"
  add_foreign_key "notifications", "users", column: "actor_id"
  add_foreign_key "profile_views", "users"
  add_foreign_key "profile_views", "users", column: "viewer_id"
  add_foreign_key "reports", "tweets"
  add_foreign_key "reports", "users"
  add_foreign_key "reports", "users", column: "reporter_id"
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
