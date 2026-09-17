class Tweet < ApplicationRecord
  belongs_to :user
  belongs_to :parent, class_name: "Tweet", optional: true
  belongs_to :retweet_of, class_name: "Tweet", optional: true

  has_many :likes, dependent: :destroy
  has_many :replies, class_name: "Tweet", foreign_key: :parent_id, dependent: :destroy
  has_many :retweets, class_name: "Tweet", foreign_key: :retweet_of_id, dependent: :destroy
  has_many :tweet_views, dependent: :destroy

  # Permanently banned accounts are filtered out of every timeline: their
  # profile withholds their information, so surfacing their posts elsewhere
  # would contradict it. Timed bans are excluded from this list because they
  # lift themselves and are resolved by `User#resolve_ban!`.
  #
  # When the operator has switched the simulated accounts off, their posts are
  # hidden here rather than filtered per controller, so the switch reaches every
  # surface - timelines, search, profiles, trends - without each one having to
  # remember to ask.
  scope :visible, lambda {
    scope = where(is_deleted: false)
            .where.not(user_id: User.where(is_banned: true, ban_permanent: true).select(:id))
    scope = scope.where.not(user_id: User.where(is_bot: true).select(:id)) if SiteSetting.hide_bots?
    scope
  }
  scope :roots,   -> { visible.where(parent_id: nil) }
  scope :recent,  -> { order(created_at: :desc, id: :desc) }

  HASHTAG_PATTERN = /(?<!\w)#([A-Za-z0-9_]{1,50})/.freeze

  # Trends are read as "what the site is talking about right now", so they are
  # drawn from a moving window rather than from the newest handful of rows, and
  # ranked by how many different accounts used the tag.
  #
  # Ranking on raw mentions alone lets one account repeating a tag outrank a
  # topic the whole site has picked up; counting distinct authors is what makes
  # the list read like a trend instead of like somebody's catchphrase.
  TREND_WINDOW = 24.hours
  TREND_SCAN_LIMIT = 5_000
  TREND_MIN_AUTHORS = 3

  def self.top_trends(limit = 8, window: TREND_WINDOW)
    rows = visible
           .where("created_at >= ?", window.ago)
           .where("body LIKE ?", "%#%")
           .recent
           .limit(TREND_SCAN_LIMIT)
           .pluck(:body, :user_id)

    mentions = Hash.new(0)
    authors = Hash.new { |hash, tag| hash[tag] = Set.new }

    rows.each do |body, user_id|
      # A tag repeated inside one tweet is still one account talking about it.
      body.to_s.scan(HASHTAG_PATTERN).flatten.map(&:downcase).uniq.each do |tag|
        mentions[tag] += 1
        authors[tag] << user_id
      end
    end

    mentions
      .select { |tag, count| authors[tag].size >= TREND_MIN_AUTHORS && count.positive? }
      .sort_by { |tag, count| [ -authors[tag].size, -count, tag ] }
      .first(limit)
      .map { |tag, count| [ tag, count, authors[tag].size ] }
  end

  def like_count
    likes.where(kind: Like::LIKE).count
  end

  def favourite_count
    likes.where(kind: Like::FAVOURITE).count
  end

  def retweet_count
    retweets.visible.count
  end

  def reply_count
    replies.visible.count
  end

  def liked_by?(user)
    return false unless user

    likes.exists?(user_id: user.id, kind: Like::LIKE)
  end

  def favourited_by?(user)
    return false unless user

    likes.exists?(user_id: user.id, kind: Like::FAVOURITE)
  end

  # True when the given account currently holds a live retweet of this tweet.
  def retweeted_by?(user)
    return false unless user

    retweets.visible.exists?(user_id: user.id)
  end
end