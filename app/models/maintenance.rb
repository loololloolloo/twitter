# Bulk maintenance operations for the admin panel.
#
# Every operation is destructive and irreversible, so each one is a single
# transaction: either the whole sweep lands or nothing does. Rows are removed
# with `delete_all` rather than `destroy_all` so a sweep over the whole site
# does not pay for per-row callbacks, and the ordering below walks the foreign
# keys from the leaves inwards so no statement is rejected mid-sweep.
module Maintenance
  # Rows that carry no meaning without the accounts and posts they point at,
  # in the order they must be removed. The operator's own account is never in
  # scope; `clear_accounts` and `reset_database` preserve it explicitly.
  CONTENT_TABLES = %w[
    DmMessage
    DmConversation
    Notification
    Like
    TweetView
    ProfileView
    Report
    Follow
    Tweet
  ].freeze

  # Counted for the confirmation copy so an operator sees the blast radius
  # before committing to it.
  def self.inventory
    {
      users: User.count,
      bots: User.where(is_bot: true).count,
      tweets: Tweet.count,
      follows: Follow.count,
      granted_followers: User.sum(:bonus_followers),
      likes: Like.count,
      notifications: Notification.count,
      conversations: DmConversation.count,
      reports: Report.count,
      sessions: Session.count
    }
  end

  # Deletes every simulated account and everything they posted. Real members
  # and their content are left alone.
  def self.clear_bot_accounts
    bots = User.where(is_bot: true)
    ids = bots.pluck(:id)
    return 0 if ids.empty?

    transaction do
      clear_authored_content(ids)
      Follow.where(follower_id: ids).or(Follow.where(followee_id: ids)).delete_all
      Like.where(user_id: ids).delete_all
      Notification.where(user_id: ids).or(Notification.where(actor_id: ids)).delete_all
      TweetView.where(user_id: ids).delete_all
      ProfileView.where(user_id: ids).or(ProfileView.where(viewer_id: ids)).delete_all
      Report.where(user_id: ids).or(Report.where(reporter_id: ids)).delete_all
      DmMessage.where(sender_id: ids).delete_all
      DmConversation.where(user_a_id: ids).or(DmConversation.where(user_b_id: ids)).delete_all
      AuditLog.where(actor_id: ids).delete_all
      Session.where(user_id: ids).delete_all
      User.where(id: ids).delete_all
    end

    ids.size
  end

  # Unfollows everyone from everyone. Accounts and posts survive; the graph
  # does not.
  #
  # Granted followers are cleared too. They are not rows in the follow graph -
  # the bot engine adds them directly once every simulated account already
  # follows, and an administrator can grant them by hand - so deleting the
  # follows alone left every profile still advertising the followers it had been
  # given, which read as the sweep not having worked.
  def self.clear_follows
    follows = Follow.count
    granted = User.sum(:bonus_followers)
    transaction do
      Follow.delete_all
      User.where("bonus_followers > 0").update_all(bonus_followers: 0)
    end
    follows + granted
  end

  # Deletes every post, including replies and retweets, along with the likes,
  # views and notifications that pointed at them.
  def self.purge_tweets
    count = Tweet.count
    transaction do
      Like.delete_all
      TweetView.delete_all
      Notification.delete_all
      Report.delete_all
      Tweet.delete_all
    end
    count
  end

  # Empties the site back to a fresh install: no members except the operator
  # running the sweep, no content, no history. Roles, permissions and site
  # settings are configuration rather than data, so they are kept.
  def self.reset_database(keep_user)
    transaction do
      CONTENT_TABLES.each { |model| model.constantize.delete_all }
      AuditLog.delete_all
      Session.where.not(user_id: keep_user.id).delete_all
      User.where.not(id: keep_user.id).delete_all
    end
  end

  # Replaces the live database with the contents of a previously exported SQL
  # dump. The whole import runs in one transaction, so a malformed dump leaves
  # the existing data untouched instead of half-replaced.
  def self.restore_database(sql)
    statements = sql.to_s.split("\n").map(&:strip).reject { |line| line.empty? || line.start_with?("--") }
    raise ArgumentError, "the file contains no SQL statements" if statements.empty?

    transaction do
      connection.execute("PRAGMA foreign_keys = OFF")
      statements.each { |statement| connection.execute(statement) }
      connection.execute("PRAGMA foreign_keys = ON")
    end

    statements.size
  end

  # Forces every member except the operator to sign in again.
  def self.clear_sessions(keep_user)
    count = Session.where.not(user_id: keep_user.id).count
    transaction { Session.where.not(user_id: keep_user.id).delete_all }
    count
  end

  # Empties the audit log. Kept separate from the other sweeps because it is
  # the record of what the other sweeps did.
  def self.clear_audit_log
    count = AuditLog.count
    transaction { AuditLog.delete_all }
    count
  end

  # Removes rows left pointing at records that no longer exist. Bulk deletes
  # and a restored dump can both strand references, and a stranded like or
  # notification shows up as a broken entry in someone's timeline.
  def self.prune_orphans
    transaction do
      Tweet.where.not(parent_id: nil).where.not(parent_id: Tweet.select(:id)).delete_all
      Tweet.where.not(retweet_of_id: nil).where.not(retweet_of_id: Tweet.select(:id)).delete_all
      Like.where.not(tweet_id: Tweet.select(:id)).delete_all
      TweetView.where.not(tweet_id: Tweet.select(:id)).delete_all
      Notification.where.not(tweet_id: nil).where.not(tweet_id: Tweet.select(:id)).delete_all
      Report.where.not(tweet_id: nil).where.not(tweet_id: Tweet.select(:id)).delete_all
      Follow.where.not(follower_id: User.select(:id)).delete_all
      Follow.where.not(followee_id: User.select(:id)).delete_all
      DmMessage.where.not(sender_id: User.select(:id)).delete_all
      DmMessage.where.not(dm_conversation_id: DmConversation.select(:id)).delete_all
    end
    User.count
  end

  # Empties the notification inbox for everyone. The posts they point at stay,
  # so a member loses the history of who reacted but not the reactions.
  def self.clear_notifications
    count = Notification.count
    transaction { Notification.delete_all }
    count
  end

  # Deletes every direct message and the conversations around them. Nobody is
  # removed; the conversations simply never happened.
  def self.clear_messages
    messages = DmMessage.count
    transaction do
      DmMessage.delete_all
      DmConversation.delete_all
    end
    messages
  end

  # Drops the per-post and per-profile view counters. Used when the numbers
  # have drifted or an operator wants the site's readership to start over.
  def self.clear_views
    count = TweetView.count + ProfileView.count
    transaction do
      TweetView.delete_all
      ProfileView.delete_all
    end
    count
  end

  # Deletes every report, open ones included. The moderation queue becomes
  # empty without touching a single account or post.
  def self.clear_reports
    count = Report.count
    transaction { Report.delete_all }
    count
  end

  # Zeroes the administrator-granted follower padding on every account. The
  # real follow rows are untouched, so profiles fall back to their true counts.
  def self.clear_granted_followers
    granted = User.sum(:bonus_followers)
    transaction { User.where("bonus_followers > 0").update_all(bonus_followers: 0) }
    granted
  end

  # Zeroes the granted like, favourite and retweet padding on every post. Real
  # engagement rows survive.
  def self.clear_granted_engagement
    granted = Tweet.sum(:bonus_likes) + Tweet.sum(:bonus_favourites) + Tweet.sum(:bonus_retweets)
    transaction do
      Tweet.where("bonus_likes > 0 OR bonus_favourites > 0 OR bonus_retweets > 0")
           .update_all(bonus_likes: 0, bonus_favourites: 0, bonus_retweets: 0)
    end
    granted
  end

  # Removes every session, the operator's included. The next request from any
  # browser lands on the sign-in page.
  def self.clear_all_sessions
    count = Session.count
    transaction { Session.delete_all }
    count
  end

  # Recompacts the SQLite database and returns the space reclaimed in bytes.
  def self.vacuum_database
    before = database_bytes
    transaction { connection.execute("VACUUM") }
    [ before - database_bytes, 0 ].max
  rescue ActiveRecord::StatementInvalid
    0
  end

  # The size of the database file on disk, in bytes. SQLite reports this itself
  # so the figure includes the write-ahead log the file listing would miss.
  def self.database_bytes
    pages = connection.select_value("PRAGMA page_count").to_i
    size = connection.select_value("PRAGMA page_size").to_i
    pages * size
  end

  # A plain-language snapshot of how much data each table holds, for the panel's
  # insights screen. Ordered by weight so the biggest tables read first.
  def self.table_weights
    {
      "Users" => User.count,
      "Tweets" => Tweet.count,
      "Likes" => Like.count,
      "Follows" => Follow.count,
      "Notifications" => Notification.count,
      "Messages" => DmMessage.count,
      "Reports" => Report.count,
      "Audit entries" => AuditLog.count,
      "Sessions" => Session.count
    }.sort_by { |_label, count| -count }
  end

  def self.clear_authored_content(user_ids)
    tweets = Tweet.where(user_id: user_ids)
    tweet_ids = tweets.pluck(:id)
    Like.where(tweet_id: tweet_ids).delete_all
    TweetView.where(tweet_id: tweet_ids).delete_all
    tweets.delete_all
  end

  def self.transaction(&block)
    ActiveRecord::Base.transaction(requires_new: true, &block)
  end

  def self.connection
    ActiveRecord::Base.connection
  end
end