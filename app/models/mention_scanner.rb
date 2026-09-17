# Finds @mentions in a tweet body and notifies the accounts named.
#
# The username pattern follows the rules the original twitter-text library
# used: letters, digits and underscores, 2-15 characters, not preceded by
# another word character or an @ (so email addresses do not match).
class MentionScanner
  MENTION_PATTERN = /(?<![\w@])@([A-Za-z0-9_]{2,15})/.freeze

  def self.usernames(body)
    body.to_s.scan(MENTION_PATTERN).flatten.uniq
  end

  def self.notify(tweet)
    return if tweet.body.blank?

    usernames(tweet.body).each do |name|
      mentioned = User.find_by("username = ? COLLATE NOCASE", name)
      next if mentioned.nil?
      next if mentioned.id == tweet.user_id

      Notification.create!(
        user: mentioned, actor: tweet.user, kind: "mention", tweet: tweet,
        body: "@#{tweet.user.username} mentioned you"
      )
    end
  end
end