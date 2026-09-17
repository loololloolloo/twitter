# Backfills history for the simulated population.
#
# A site where five thousand accounts just appeared would have an empty
# timeline and no social graph, which is not what an established service looks
# like. This gives every bot a standing set of follows and a trail of posts,
# likes and retweets dated over the preceding days, all written in bulk.
#
# The engine then keeps that activity moving forward in real time.
module BotSeeder
  # How far back to write history. A week gives the timeline depth without
  # making the backfill expensive.
  HISTORY_DAYS = 7
  # Caps that keep the backfill to a size SQLite handles comfortably: roughly
  # 50k posts, 250k likes and 150k follows for a 5,000 account population.
  MAX_POSTS_PER_BOT = 14
  # Account-backed reactions per post. The population is a few thousand, so a
  # busy post is given a long tail of extra engagement on top of these - see
  # `engagement_tail`.
  MAX_LIKERS_PER_TWEET = 9
  # How often a post is one of the site's popular ones. Most posts are ordinary
  # and only a small share carry the big numbers, which is the shape a real
  # timeline has.
  VIRAL_SHARE = 0.03
  # The spread of the tail on a popular post. Drawn log-uniformly across this
  # range so there are a few enormous hits and a broad slope beneath them
  # rather than a cluster of posts all sitting at the same figure.
  VIRAL_RANGE = 8_000..600_000
  # A member's post is pushed up the tail: real accounts are what the site is
  # for, so their posts should be among the ones that carry real numbers.
  MEMBER_TAIL_FLOOR = 250
  FOLLOW_BATCH = 5_000
  TWEET_BATCH = 2_000
  LIKE_BATCH = 5_000

  class << self
    # Gives bots that have no follows yet a starting social graph, preferring
    # to follow members, then other bots.
    def seed_follows
      humans = User.humans.pluck(:id)
      bot_ids = User.bots.pluck(:id)
      return 0 if bot_ids.empty?

      existing = Follow.pluck(:follower_id, :followee_id).to_set
      rows = []
      now = Time.current

      User.bots.pluck(:id, :persona).each do |bot_id, persona_json|
        persona = JSON.parse(persona_json.presence || "{}") rescue {}
        want = (persona["follows_at_start"].presence || 40).to_i

        # Most members are followed by most bots, so the human accounts sit at
        # the centre of the graph rather than being isolated.
        targets = humans.first(30)
        filler = bot_ids.sample([ want, bot_ids.size ].min)
        (targets + filler).uniq.first(want).each do |target_id|
          next if target_id == bot_id
          next if existing.include?([ bot_id, target_id ])

          existing << [ bot_id, target_id ]
          rows << { follower_id: bot_id, followee_id: target_id, created_at: now, updated_at: now }
        end

        flush_follows(rows) if rows.size >= FOLLOW_BATCH
      end

      flush_follows(rows)
    end

    def flush_follows(rows)
      Follow.insert_all(rows) if rows.any?
      rows.clear
    end

    # Writes backdated posts so timelines, profiles and trends have content the
    # moment the population exists.
    def seed_tweets
      bot_ids = User.bots.pluck(:id)
      return 0 if bot_ids.empty?

      rows = []
      now = Time.current

      User.bots.find_each do |bot|
        persona = bot.persona_hash
        per_day = persona["posts_per_day"].to_f
        next if per_day <= 0

        # Total posts for the backfill window, capped so one heavy persona
        # cannot dominate the insert.
        count = [ (per_day * HISTORY_DAYS).round, MAX_POSTS_PER_BOT ].min

        count.times do
          body = ContentGenerator.tweet(persona)
          next if body.blank?

          posted = now - (rand * HISTORY_DAYS * 86_400).seconds
          rows << {
            user_id: bot.id,
            body: body,
            created_at: posted,
            updated_at: posted,
            is_deleted: false,
            is_pinned: false
          }
        end

        if rows.size >= TWEET_BATCH
          Tweet.insert_all(rows)
          rows.clear
        end
      end

      Tweet.insert_all(rows) if rows.any?
    end

    # Distributes likes and retweets across the tweets that now exist, so post
    # counts look earned rather than zero across the board.
    def seed_engagement
      # Only original posts are engaged with; retweets are not cascaded further.
      posts = Tweet.visible.where(parent_id: nil, retweet_of_id: nil).pluck(:id, :user_id, :created_at)
      return 0 if posts.empty?

      tweet_created_at = posts.each_with_object({}) { |(id, _, at), map| map[id] = at }
      tweet_ids = posts.map { |id, author_id, _| [ id, author_id ] }
      bot_ids = User.bots.pluck(:id)
      like_rows = []
      rt_rows = []
      tail_rows = []
      member_ids = User.humans.pluck(:id).to_set
      now = Time.current

      tweet_ids.each do |tweet_id, author_id|
        # Engagement is dated shortly after the post it belongs to, within the
        # history window, so the timeline shows a natural trickle rather than
        # thousands of retweets appearing at the same instant.
        when_ = (tweet_created_at[tweet_id] || now) + rand(0..72).hours
        when_ = now if when_ > now

        # A few to a few dozen engagements per post, weighted toward the low
        # end so a handful of posts look popular and most look ordinary.
        likers = bot_ids.sample(rand(1..MAX_LIKERS_PER_TWEET))
        likers.each do |bot_id|
          next if bot_id == author_id

          like_rows << { user_id: bot_id, tweet_id: tweet_id, created_at: when_, updated_at: when_ }
        end

        bot_ids.sample(rand(0..2)).each do |bot_id|
          next if bot_id == author_id

          rt_rows << {
            user_id: bot_id, body: "", retweet_of_id: tweet_id,
            created_at: when_, updated_at: when_, is_deleted: false, is_pinned: false
          }
        end

        tail_rows << [ tweet_id, engagement_tail(author_id, member_ids) ]

        flush_likes(like_rows) if like_rows.size >= LIKE_BATCH
        flush_rts(rt_rows) if rt_rows.size >= TWEET_BATCH
        flush_tails(tail_rows) if tail_rows.size >= TWEET_BATCH
      end

      flush_likes(like_rows)
      flush_rts(rt_rows)
      flush_tails(tail_rows)
    end

    # The engagement a post carries beyond the reactions that have an account
    # behind them, which is what lets a post show numbers larger than the
    # population. Zero for an ordinary post, so most of the timeline stays
    # modest; a small share draws a figure spread across VIRAL_RANGE, giving the
    # handful of hits a long tail beneath them. A member's own posts are always
    # given at least MEMBER_TAIL_FLOOR, so real accounts are not drowned out by
    # the simulated ones.
    def engagement_tail(author_id, member_ids)
      base = rand < VIRAL_SHARE ? log_uniform(VIRAL_RANGE) : 0
      return base unless member_ids.include?(author_id)

      [ base, MEMBER_TAIL_FLOOR ].max
    end

    # A value drawn evenly across the orders of magnitude in the range, so each
    # power of ten is equally likely and the result reads as a long tail rather
    # than a uniform smear.
    def log_uniform(range)
      low = Math.log10(range.first)
      high = Math.log10(range.last)
      (10**(low + rand * (high - low))).round
    end

    # Writes a batch of tails as one statement per counter, rather than a save
    # per post. The same shares the engine uses split each post's total, so a
    # seeded post and one the engine goes on to bump stay in proportion.
    def flush_tails(rows)
      return if rows.empty?

      totals = rows.to_h
      BotEngine::ENGAGEMENT_SHARES.each do |column, share|
        values = totals.transform_values { |total| (total * share).round }
        next if values.values.all?(&:zero?)

        cases = values.map { |id, value| "WHEN #{id.to_i} THEN #{value.to_i}" }.join(" ")
        Tweet.where(id: values.keys).update_all("#{column} = CASE id #{cases} END")
      end

      rows.clear
    end

    def flush_likes(rows)
      Like.insert_all(rows) if rows.any?
      rows.clear
    end

    def flush_rts(rows)
      Tweet.insert_all(rows) if rows.any?
      rows.clear
    end
  end
end