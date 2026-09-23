class Tweet < ApplicationRecord
  belongs_to :user
  belongs_to :parent, class_name: "Tweet", optional: true
  belongs_to :retweet_of, class_name: "Tweet", optional: true
  # A quote tweet is its own post that attaches another: the body belongs to the
  # quoting account, and the quoted post is shown beneath it.
  belongs_to :quote_of, class_name: "Tweet", optional: true

  has_many :likes, dependent: :destroy
  has_many :replies, class_name: "Tweet", foreign_key: :parent_id, dependent: :destroy
  has_many :retweets, class_name: "Tweet", foreign_key: :retweet_of_id, dependent: :destroy
  has_many :quotes, class_name: "Tweet", foreign_key: :quote_of_id, dependent: :destroy
  has_many :tweet_views, dependent: :destroy
  has_many :bookmarks, dependent: :destroy
  # A post carries at most one poll, and it belongs to the post: deleting the
  # post takes its choices and votes with it.
  has_one  :poll, dependent: :destroy

  # Permanently banned accounts are filtered out of every timeline: their
  # profile withholds their information, so surfacing their posts elsewhere
  # would contradict it. Timed bans are excluded from this list because they
  # lift themselves and are resolved by `User#resolve_ban!`.
  scope :visible, lambda {
    scope = where(is_deleted: false)
      .where.not(user_id: User.where(is_banned: true, ban_permanent: true).select(:id))
      # A post whose schedule has not arrived is withheld from every reader,
      # the author included; the author's own scheduled list is the one place
      # that reads past this. Folded in here, beside the other visibility
      # rules, so every timeline inherits it from one place.
      .merge(not_scheduled)

    # Posts matching a "hide" blocked term are dropped here, alongside the other
    # visibility rules, so every timeline inherits the rule from one place. The
    # term list is compiled and cached, so this is a bound NOT (...) rather than
    # a rescan of the world per request. "Flag" terms deliberately do not appear
    # here: a flagged post stays visible and is only marked in the panel.
    condition = BlockedTerm.matcher.hide_sql
    condition ? scope.where("NOT (#{condition.first})", *condition.last) : scope
  }

  # Posts matching any of the given terms. The SQL is compiled by BlockedTerm
  # and shared with the timeline's exclusion, so a term that hides a post here
  # and a term that lists it there can never disagree.
  scope :matching_terms, lambda { |terms|
    condition = BlockedTerm.like_condition(terms)
    condition ? where(condition.first, *condition.last) : none
  }

  # Posts matching a term in flag mode, read from the compiled matcher rather
  # than re-reading the list, so the review screen and the timeline agree about
  # which terms are in force.
  scope :matching_flags, lambda {
    condition = BlockedTerm.matcher.flag_sql
    condition ? where(condition.first, *condition.last) : none
  }
  # Posts a schedule is still holding back, and the rows whose moment has
  # arrived. The two are complements over the same stamp; a post made now - the
  # ordinary case - has no schedule at all and belongs to neither, so both read
  # `scheduled_at` against the clock rather than assuming a schedule is set.
  scope :scheduled, -> { where("tweets.scheduled_at > ?", Time.current) }
  scope :not_scheduled, -> { where("tweets.scheduled_at IS NULL OR tweets.scheduled_at <= ?", Time.current) }

  scope :roots,   -> { visible.where(parent_id: nil) }
  scope :recent,  -> { order(created_at: :desc, id: :desc) }

  # Replies the author has hidden are dropped for everybody except their own
  # author, who still sees them greyed so the thread reads whole. This is a
  # scope rather than a column check at each call site because every thread read
  # has to apply the same rule.
  scope :not_hidden, -> { where(reply_hidden_at: nil) }

  # Posts that are neither retweets nor quotes: the "original posts" a profile's
  # default tab and the counts are built from.
  scope :originals, -> { where(retweet_of_id: nil, quote_of_id: nil) }

  # Posts carrying an attachment of any kind. A post has media when it has
  # either a stored file or an embedded link, and both count for the media
  # tabs, so this is a scope rather than a `media_path` check at each site.
  scope :with_media, -> { where.not(media_path: [ nil, "" ]).or(where.not(media_url: [ nil, "" ])) }

  # Posts carrying a video file. The extension is the only signal available in
  # SQL, so the pattern is built from the same list the uploader accepts and
  # cannot drift from it. The list is a frozen constant of literal extensions,
  # interpolated rather than bound: an array bind would be taken as a row value.
  scope :videos, -> {
    likes = Uploads::ALLOWED_VIDEO_EXT.map { |ext| "tweets.media_path LIKE '%#{ext}'" }.join(" OR ")
    where(media_url: [ nil, "" ]).where("(#{likes})")
  }

  # Whether a schedule is still holding this post back. Read against the clock
  # rather than cached, because a scheduled post becomes live on its own with no
  # writer to flip a flag; deriving it is what makes a moment in time enough.
  def scheduled_pending?
    scheduled_at.present? && scheduled_at > Time.current
  end

  # The time a reader should see on the post. For a scheduled post that is the
  # moment it will go out, not the moment the draft was written; for everything
  # else it is when it was posted.
  def timeline_at
    scheduled_pending? ? scheduled_at : created_at
  end

  # Whether this post carries an attachment: a stored file or an embedded link.
  def media_attached?
    media_path.present? || media_url.present?
  end

  # Whether the attachment is a video, so a view can choose a player over an
  # image without repeating the extension test.
  def video?
    media_url.blank? && Uploads.video?(media_path)
  end

  # Removes the posts of accounts the viewer has blocked (either way) or muted,
  # and the posts of protected accounts the viewer does not follow. Applied to
  # every timeline and search so one rule covers the site.
  #
  # A nil viewer filters only protected accounts, which is what a signed-out
  # read should see.
  scope :readable_by, lambda { |viewer|
    scope = all
    unless viewer.nil?
      silenced = viewer.silenced_account_ids
      scope = scope.where.not(user_id: silenced) if silenced.any?
    end

    # A protected account's posts are readable only by itself and its approved
    # followers. Expressed as: not protected, or mine, or I follow them.
    protected_ids = User.where(protected: true).select(:id)
    scope = if viewer.nil?
      scope.where.not(user_id: protected_ids)
    else
      mine = viewer.id
      followed = Follow.where(follower_id: viewer.id).select(:followee_id)
      scope.where.not(user_id: protected_ids)
           .or(scope.where(user_id: mine))
           .or(scope.where(user_id: followed))
    end
  }

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

  # Trends move slowly - they are a rolling 24-hour window - so the result is
  # cached briefly rather than recomputed on every home and explore render,
  # where it was the most expensive part of the page. The scan is bounded but
  # it still reads five thousand rows and groups them in Ruby.
  TRENDS_CACHE_TTL = 60.seconds

  def self.top_trends(limit = 8, window: TREND_WINDOW)
    Rails.cache.fetch("tweet_top_trends/#{limit}/#{window.to_i}", expires_in: TRENDS_CACHE_TTL) do
      compute_top_trends(limit, window: window)
    end
  end

  def self.compute_top_trends(limit, window: TREND_WINDOW)
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

  # Displayed counts. Real reactions from accounts are counted from their own
  # tables and the bonus carries what has no rows behind it, so the figure a
  # post shows is not limited by how many accounts exist.
  def like_count
    bonus_likes.to_i + likes.where(kind: Like::LIKE).count
  end

  def favourite_count
    bonus_favourites.to_i + likes.where(kind: Like::FAVOURITE).count
  end

  def retweet_count
    bonus_retweets.to_i + retweets.visible.count
  end

  def reply_count
    replies.visible.count
  end

  # The account a post answers, when the viewer is allowed to be told. 2019
  # labelled every reply with "Replying to @handle" in the timeline, but only
  # for a parent the viewer could already open: naming a protected or banned
  # account the viewer cannot read would leak the very account the visibility
  # rule withholds, so those replies render without the line.
  def reply_target(viewer)
    return nil if parent_id.nil?

    parent = self.parent
    return nil if parent.nil?
    return nil if parent.is_deleted?
    return nil if parent.user.permanently_banned?
    return nil unless parent.user.readable_by?(viewer)

    parent.user
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

  def bookmarked_by?(user)
    return false unless user

    bookmarks.exists?(user_id: user.id)
  end

  # A reply is hidden from everyone but the author of the parent post, who is
  # the only account that can hide or reveal it.
  def reply_hidden?
    reply_hidden_at.present?
  end

  def hide_reply!
    update!(reply_hidden_at: Time.current)
  end

  def unhide_reply!
    update!(reply_hidden_at: nil)
  end

  def quote_count
    quotes.visible.count
  end

  # The post this one attaches, whether as a retweet or a quote. Used by the
  # partial, which renders the attached post beneath the quoting body.
  def attached
    retweet_of || quote_of
  end
end