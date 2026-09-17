# Imports the accounts and content from the original SQLite database into the
# ActiveRecord schema. Password hashes are copied verbatim, so existing accounts
# keep their current passwords.
#
# Usage: LEGACY_DB=/tmp/twitter-original.db ./bin/bundle exec rails runner db/import_legacy.rb
require "sqlite3"

legacy_path = ENV.fetch("LEGACY_DB", "/tmp/twitter-original.db")
abort "Legacy database not found at #{legacy_path}" unless File.exist?(legacy_path)

legacy = SQLite3::Database.new(legacy_path)
legacy.results_as_hash = true

def rows(db, sql)
  db.execute(sql)
rescue SQLite3::SQLException => e
  warn "  skipped (#{e.message.split("\n").first})"
  []
end

ActiveRecord::Base.transaction do
  Role.delete_all
  Permission.delete_all
  User.delete_all
  Tweet.delete_all
  Follow.delete_all
  Like.delete_all
  Notification.delete_all
  AuditLog.delete_all
  Session.delete_all
  DmConversation.delete_all
  DmMessage.delete_all
  SiteSetting.delete_all

  # Roles
  rows(legacy, "SELECT id, name, description, rank FROM roles ORDER BY id").each do |r|
    Role.create!(id: r["id"], name: r["name"], description: r["description"], rank: r["rank"])
  end
  puts "roles: #{Role.count}"

  # Permissions
  rows(legacy, "SELECT id, key, label FROM permissions ORDER BY id").each do |p|
    Permission.create!(id: p["id"], key: p["key"], label: p["label"])
  end
  puts "permissions: #{Permission.count}"

  rows(legacy, "SELECT role_id, permission_id FROM role_permissions").each do |rp|
    RolePermission.create!(role_id: rp["role_id"], permission_id: rp["permission_id"])
  end
  puts "role_permissions: #{RolePermission.count}"

  # Users - password_hash copied as-is
  rows(legacy, "SELECT * FROM users ORDER BY id").each do |u|
    User.create!(
      id: u["id"],
      username: u["username"],
      display_name: u["display_name"],
      email: u["email"],
      password_hash: u["password_hash"],
      bio: u["bio"].to_s,
      location: u["location"].to_s,
      website: u["website"].to_s,
      avatar_path: u["avatar_path"],
      banner_path: u["banner_path"],
      role_id: u["role_id"],
      is_suspended: u["is_suspended"] == 1,
      is_verified: u["is_verified"] == 1,
      is_banned: u["is_banned"] == 1,
      ban_reason: u["ban_reason"].to_s,
      ban_permanent: u["ban_permanent"] == 1,
      ban_expires_at: u["ban_expires_at"],
      bonus_followers: u["bonus_followers"].to_i,
      last_login_at: u["last_login_at"],
      created_at: u["created_at"] || Time.current,
      updated_at: u["created_at"] || Time.current
    )
  end
  puts "users: #{User.count}"

  rows(legacy, "SELECT * FROM tweets ORDER BY id").each do |t|
    Tweet.create!(
      id: t["id"], user_id: t["user_id"], body: t["body"].to_s,
      parent_id: t["parent_id"], retweet_of_id: t["retweet_of_id"],
      media_path: t["media_path"], is_deleted: t["is_deleted"] == 1,
      created_at: t["created_at"] || Time.current, updated_at: t["created_at"] || Time.current
    )
  end
  puts "tweets: #{Tweet.count}"

  rows(legacy, "SELECT * FROM likes").each do |l|
    Like.create!(user_id: l["user_id"], tweet_id: l["tweet_id"],
                 created_at: l["created_at"] || Time.current)
  end
  puts "likes: #{Like.count}"

  rows(legacy, "SELECT * FROM follows").each do |f|
    Follow.create!(follower_id: f["follower_id"], followee_id: f["followee_id"],
                   created_at: f["created_at"] || Time.current)
  end
  puts "follows: #{Follow.count}"

  rows(legacy, "SELECT * FROM notifications ORDER BY id").each do |n|
    Notification.create!(
      id: n["id"], user_id: n["user_id"], actor_id: n["actor_id"], kind: n["kind"],
      tweet_id: n["tweet_id"], body: n["body"].to_s, is_read: n["is_read"] == 1,
      created_at: n["created_at"] || Time.current
    )
  end
  puts "notifications: #{Notification.count}"

  rows(legacy, "SELECT * FROM audit_log ORDER BY id").each do |a|
    AuditLog.create!(id: a["id"], actor_id: a["actor_id"], action: a["action"],
                     target: a["target"].to_s, detail: a["detail"].to_s,
                     created_at: a["created_at"] || Time.current)
  end
  puts "audit_logs: #{AuditLog.count}"

  rows(legacy, "SELECT * FROM site_settings").each do |s|
    SiteSetting.create!(key: s["key"], value: s["value"].to_s)
  end
  puts "site_settings: #{SiteSetting.count}"

  rows(legacy, "SELECT * FROM dm_conversations ORDER BY id").each do |c|
    DmConversation.create!(id: c["id"], user_a_id: c["user_a"], user_b_id: c["user_b"],
                           created_at: c["created_at"] || Time.current)
  end

  rows(legacy, "SELECT * FROM dm_messages ORDER BY id").each do |m|
    DmMessage.create!(id: m["id"], dm_conversation_id: m["conversation_id"],
                      sender_id: m["sender_id"], body: m["body"],
                      created_at: m["created_at"] || Time.current)
  end
  puts "dm_conversations: #{DmConversation.count}  dm_messages: #{DmMessage.count}"
end

# SQLite AUTOINCREMENT counters must move past the imported ids or later inserts
# will try to reuse them.
%w[users tweets notifications audit_logs dm_conversations dm_messages roles permissions].each do |t|
  max = ActiveRecord::Base.connection.select_value("SELECT COALESCE(MAX(id), 0) FROM #{t}")
  ActiveRecord::Base.connection.execute(
    "INSERT OR REPLACE INTO sqlite_sequence (name, seq) VALUES ('#{t}', #{max})"
  )
rescue StandardError => e
  warn "  sequence bump skipped for #{t}: #{e.message}"
end

puts "\nImport complete."