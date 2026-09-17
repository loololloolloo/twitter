# Drives continuous, human-shaped activity for simulated accounts.
#
# A single `tick` does the work for every bot that is due: it consults each
# persona to decide what that account would do next, performs it, and books the
# account's following action. Nothing here runs a thread per bot - the whole
# population is driven by repeated ticks, which keeps the load bounded and lets
# the runner honour the site's write capacity.
#
# Two rules keep the simulation from looking like a machine:
#
#   * Timing is uneven. Each persona has a daily rhythm, so an account sleeps
#     during its own night; the gap between actions is drawn from a
#     distribution rather than being a fixed interval.
#   * Humans are preferred. When a bot chooses someone to interact with, real
#     accounts and their content are weighted far above other bots, so members
#     see responses to their own posts.
class BotEngine
  # Weighted behaviour mix. Which action a bot takes depends on its persona
  # rates (see `choose_action`), not on this table alone.
  #
  # `view`, `browse` and `scroll` are the passive half of a session. They leave
  # no public trace beyond an impression, but they dominate the mix because
  # that is what people actually spend their time doing: reading far more than
  # they write. Without them a bot's history is all output and no reading,
  # which no real account looks like.
  ACTIONS = %i[post like retweet reply follow dm view browse scroll].freeze

  # A real member's content is this many times more likely to be engaged with
  # than another bot's, so humans get noticed.
  HUMAN_WEIGHT = 12

  # Bots engage each other a little more readily than a flat weighting would
  # give, so the simulated population has its own life instead of only ever
  # orbiting the real members. Humans still come first.
  BOT_WEIGHT = 2.4

  # How many candidates to pull when choosing a tweet to engage with.
  CANDIDATE_POOL = 120

  # The engine keeps bots at least this sociable. Weighting alone let replies
  # all but vanish, because likes and posts are far more frequent than
  # conversations; these floors guarantee a bot's history contains visible
  # interaction with other accounts.
  INTERACTION_FLOOR = {
    reply: 0.14,
    retweet: 0.16,
    follow: 0.10,
    dm: 0.05
  }.freeze

  # Chance that a bot answers a reply it receives. Leaving this out made
  # conversations one-sided: a bot would reply and never hear back, so thread
  # depth never grew.
  REPLY_BACK_RATE = 0.55

  # The account the population reacts to as a group. When this member posts,
  # the whole population drops what it was doing and answers that post,
  # producing a visible wave of likes, retweets, replies and follows within
  # seconds rather than the gradual trickle ordinary activity produces.
  SPOTLIGHT_SETTING = "spotlight_username".freeze
  SPOTLIGHT_DEFAULT = "twitter".freeze

  # How long after the spotlight account posts the population keeps reacting.
  SPOTLIGHT_WINDOW = 30.minutes

  # How long a computed spotlight is trusted before it is looked up again.
  # Short, so a fresh post is picked up almost immediately.
  SPOTLIGHT_CACHE = 10.seconds

  # How many bots answer the post inline, in the same request that created it.
  # Everyone else is made due in one statement and drained by the runner on its
  # next pass, so the wave keeps arriving without the web request doing the
  # whole population's work.
  RALLY_INLINE = 150

  # Ceiling on replies to a single post. Every bot reading the post is the
  # intent, but a thread with one reply per bot is unreadable, so once this many
  # have answered the rest like or retweet instead. Likes, views and follower
  # growth stay uncapped.
  REPLY_CAP_PER_TWEET = 120

  # Followers the watched account gains for each post, and again on every tick
  # while the wave is still running. There is deliberately no ceiling on the
  # follower total: an account that keeps posting keeps growing, and once every
  # simulated account already follows, the rest is granted directly. Both rates
  # can be overridden from the admin settings screen.
  GROWTH_PER_POST = 500
  GROWTH_PER_TICK = 5

  # Site-setting keys for the rates above. The per-tick figure is small on
  # purpose, so growth reads as steady rather than as a number that jumps by
  # thousands every couple of seconds.
  GROWTH_POST_SETTING = "followers_per_post".freeze
  GROWTH_TICK_SETTING = "followers_per_tick".freeze

  class << self
    # Performs one action for each of the `count` bots that are due soonest.
    # Returns the number of actions completed.
    #
    # While the watched account is active there is no cap: a post from that
    # member is meant to be answered by the whole population, so the runner
    # works through every bot that was made due rather than a slice of them.
    # Each action is independent and short, and `next_delay` rebooks every bot
    # it touches, so draining the backlog in one pass is bounded work - the
    # cap would only spread the same attention thin over the following minutes,
    # which is exactly what makes a wave look like a trickle.
    def tick(count: 40)
      watching = spotlight_user
      scope = User.where(is_bot: true)
                  .where("next_action_at IS NULL OR next_action_at <= ?", Time.current)
                  .order(Arel.sql("next_action_at IS NOT NULL, next_action_at ASC"))

      scope = scope.limit(count) unless watching

      due = scope.to_a
      completed = due.count { |bot| perform(bot) }

      # The watcher's audience keeps growing for as long as the wave lasts, so
      # a single post turns into a rising follower count rather than one fixed
      # bump. Growth is applied to the configured account only: `spotlight_user`
      # can also resolve to whoever posted most recently, and those are ordinary
      # members who should not gain followers from the simulation.
      account = watched_account
      grow_followers(account, growth_per_tick) if account && posted_recently?(account)

      completed
    end

    # How many followers the watched account gains, taken from the admin-settable
    # values when present and the built-in defaults otherwise. An explicit zero
    # is honoured - it switches growth off - while a missing or unusable value
    # falls back to the default.
    def growth_per_post
      growth_rate(GROWTH_POST_SETTING, GROWTH_PER_POST)
    end

    def growth_per_tick
      growth_rate(GROWTH_TICK_SETTING, GROWTH_PER_TICK)
    end

    def growth_rate(key, fallback)
      raw = SiteSetting.get(key).to_s
      # Only a plain number counts. Anything else - a missing key, a blank box,
      # stray text - falls back, which is different from a deliberate "0".
      return fallback unless raw.match?(/\A\d+\z/)

      raw.to_i
    end

    # Drops the memoised spotlight so a change to the watched account is picked
    # up immediately rather than up to SPOTLIGHT_CACHE later.
    def reset_spotlight!
      @spotlight = {}
    end

    # The configured account itself, whether or not it has posted recently.
    # Separate from `spotlight_user`, which answers "who is the population
    # reacting to right now" and may name a different member.
    def watched_account
      User.not_suspended.where(is_bot: false)
          .find_by("username = ? COLLATE NOCASE", spotlight_username)
    end

    # When the watched account posts, the whole population reacts to that post.
    # Every eligible bot is made due in a single statement; a first slice is
    # answered inline so the post visibly lands the moment it is created, and
    # the runner drains the rest on its next pass.
    #
    # There is no cap on how many bots take part. The attention is the point,
    # and the work is bounded because the reaction per bot is one cheap action
    # and everyone is rebooked afterwards. Returns the number answered inline.
    def rally_to(tweet, inline: RALLY_INLINE)
      return 0 if tweet.nil? || tweet.user.nil?
      return 0 unless tweet.user.is_bot == false
      return 0 unless watching?(tweet.user)

      eligible = User.where(is_bot: true, is_suspended: false, is_banned: false)
                     .where.not(id: tweet.user_id)

      # One statement makes the entire population due, so a tick that was going
      # to run in a moment drains everyone at once rather than in batches.
      # Whether it changed anything says nothing about whether there is an
      # audience, so the wave still runs when everyone was already due.
      eligible.where("next_action_at IS NULL OR next_action_at > ?", Time.current)
              .update_all(next_action_at: Time.current)

      # Answer part of the wave here and now, before the response is rendered.
      sample = inline.to_i.positive? ? eligible.order(:id).limit(inline) : eligible.none

      performed = sample.count { |bot| perform(bot, focus: tweet) }

      # The post itself brings followers with it, on top of whatever the wave
      # adds, so the count jumps immediately and then keeps climbing.
      grow_followers(tweet.user, growth_per_post)

      performed
    end

    # Grows the watched account's audience without a ceiling.
    #
    # Two mechanisms, in order. While simulated accounts remain that do not
    # follow yet, they are subscribed for real, which is the part that shows up
    # in the follower list and produces notifications. Once every one of them
    # follows, the remaining growth is granted as an administrator bonus, so the
    # displayed total carries on rising instead of stalling at the population
    # size. Returns the number added.
    def grow_followers(user, amount)
      return 0 if user.nil? || user.is_bot? || amount.to_i <= 0

      wanted = amount.to_i
      followers = Follow.where(followee_id: user.id).select(:follower_id)
      candidates = User.where(is_bot: true, is_suspended: false, is_banned: false)
                       .where.not(id: user.id)
                       .where.not(id: followers)
                       .order(Arel.sql("RANDOM()"))
                       .limit(wanted)
                       .pluck(:id, :username)

      joined = candidates.size
      if joined.positive?
        now = Time.current
        rows = candidates.map do |id, _name|
          { follower_id: id, followee_id: user.id, created_at: now, updated_at: now }
        end
        Follow.insert_all(rows)

        notifications = candidates.map do |id, username|
          { user_id: user.id, actor_id: id, kind: "follow", body: "@#{username} followed you",
            created_at: now, updated_at: now }
        end
        Notification.insert_all(notifications) if notifications.any?
      end

      # The population is exhausted, so grant the rest directly. This is what
      # keeps the account growing past the number of simulated followers.
      granted = wanted - joined
      user.update_columns(bonus_followers: user.bonus_followers.to_i + granted) if granted.positive?

      wanted
    rescue ActiveRecord::RecordNotUnique
      # A concurrent grow is harmless; the next call tops the count up.
      0
    end

    # True when this account is the one the population watches.
    def watching?(user)
      return false if user.nil? || user.is_bot?

      user.username.to_s.casecmp?(spotlight_username)
    end

    # Acts for a specific bot, so a single account can be exercised directly.
    #
    # `focus` names the exact tweet the bot should react to. It is set when the
    # watched member posts, so the crowd answers that post rather than
    # whatever happens to be newest by the time each bot runs.
    def perform(bot, focus: nil)
      return false unless bot.is_bot?
      return false unless bot.active?

      persona = bot.persona_hash
      rng = Random.new
      mind = BotMind.load(bot)

      if focus
        perform_spotlight(bot, persona, mind, rng, focus.user, focus: focus)
      elsif (spotlight = spotlight_user)
        # A member everybody is watching changes what the population does: bots
        # drop what they were doing and react to that account first.
        perform_spotlight(bot, persona, mind, rng, spotlight)
      else
        case choose_action(persona, rng, mind)
        when :post    then do_post(bot, persona, rng, mind)
        when :like    then do_like(bot, persona, rng, mind)
        when :retweet then do_retweet(bot, persona, rng, mind)
        when :reply   then do_reply(bot, persona, rng, mind)
        when :follow  then do_follow(bot, persona, rng, mind)
        when :dm      then do_dm(bot, persona, rng, mind)
        when :view    then do_view(bot, persona, rng, mind)
        when :browse  then do_browse(bot, persona, rng, mind)
        when :scroll  then do_scroll(bot, persona, rng, mind)
        end
      end

      mind.tick!
      mind.save

      bot.update_columns(
        last_action_at: Time.current,
        next_action_at: next_delay(persona, rng),
        actions_performed: bot.actions_performed.to_i + 1
      )
      true
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      # A duplicate follow or like is harmless; just rebook the account rather
      # than letting one collision stall the runner.
      bot.update_columns(next_action_at: next_delay(bot.persona_hash, Random.new))
      false
    end

    # The account the whole population is currently paying attention to, or nil
    # if nobody is. Recomputed only when it goes stale so the runner is not
    # querying on every action.
    def spotlight_user
      @spotlight ||= {}
      cached = @spotlight[:value]
      return cached if cached && @spotlight[:until] && @spotlight[:until] > Time.current

      @spotlight[:value] = find_spotlight
      @spotlight[:until] = SPOTLIGHT_CACHE.from_now
      @spotlight[:value]
    end

    # A real member counts as the centre of attention when they have just been
    # posting. Bots then engage that account rather than the general pool.
    def find_spotlight
      # The configured account comes first: when this member posts, the whole
      # population reacts, which is what makes their timeline fill up at once.
      named = User.not_suspended.where(is_bot: false)
                  .find_by("username = ? COLLATE NOCASE", spotlight_username)
      if named && posted_recently?(named)
        return named
      end

      candidates = User.not_suspended.where(is_bot: false).to_a
      return nil if candidates.empty?

      recent = Tweet.where(user_id: candidates.map(&:id))
                    .where("created_at >= ?", SPOTLIGHT_WINDOW.ago)
                    .group(:user_id)
                    .count
      return nil if recent.empty?

      pick = recent.max_by { |user_id, count| count + (verified?(user_id) ? 5 : 0) }
      return nil if pick.nil?

      User.find_by(id: pick.first)
    end

    def spotlight_username
      SiteSetting.get(SPOTLIGHT_SETTING).presence || SPOTLIGHT_DEFAULT
    end

    def posted_recently?(user)
      user.tweets.visible.where("created_at >= ?", SPOTLIGHT_WINDOW.ago).exists?
    end

    def verified?(user_id)
      User.where(id: user_id, is_verified: true).exists?
    end

    # Reacts to the spotlight account: likes, retweets, replies, follows and
    # messages, all aimed at that member, so a post from them lands in a wave
    # of visible activity instead of a trickle.
    def perform_spotlight(bot, persona, mind, rng, spotlight, focus: nil)
      return if spotlight.nil? || spotlight.id == bot.id

      # Answer the specific post when one was named, otherwise the newest.
      tweet = focus || spotlight.tweets.visible.recent.first
      roll = rng.rand

      # Everyone reads it first; some like, some retweet, some answer.
      if tweet
        TweetView.record!(user: bot, tweet: tweet, dwell_seconds: dwell_time(persona, rng))

        # Once a post has enough answers the conversation turns into a wall, so
        # later arrivals read and like instead of piling on another reply.
        answering = roll >= 0.58 && roll < 0.82 && replies_to(tweet) < REPLY_CAP_PER_TWEET

        if roll < 0.34
          Like.find_or_create_by!(user: bot, tweet: tweet) if tweet.user_id != bot.id
        elsif roll < 0.58
          do_retweet_of(bot, persona, rng, mind, tweet)
        elsif answering
          do_reply_to(bot, persona, rng, mind, tweet)
        elsif roll < 0.82
          Like.find_or_create_by!(user: bot, tweet: tweet)
        elsif roll < 0.9
          follow_spotlight(bot, persona, rng, spotlight)
        else
          do_dm_to(bot, persona, rng, mind, spotlight)
        end
        return
      end

      follow_spotlight(bot, persona, rng, spotlight)
    end

    def replies_to(tweet)
      Tweet.where(parent_id: tweet.id, is_deleted: false).count
    end

    # Retweets a specific tweet rather than a weighted pick.
    def do_retweet_of(bot, persona, rng, mind, tweet)
      return if tweet.nil? || tweet.user_id == bot.id
      return if bot.tweets.exists?(retweet_of_id: tweet.id)

      Tweet.create!(user: bot, body: "", retweet_of: tweet)
      mind.absorb!(tweet.body, from_id: tweet.user_id, weight: 1.5)

      if tweet.user_id != bot.id
        Notification.create!(user: tweet.user, actor: bot, kind: "retweet",
                             tweet: tweet, body: "@#{bot.username} retweeted your tweet")
      end
    end

    # Replies to a specific tweet, and books the answered account to answer
    # back, so the thread continues instead of dying after one message.
    def do_reply_to(bot, persona, rng, mind, tweet)
      return if tweet.nil? || tweet.user_id == bot.id

      body = ContentGenerator.reply(persona, tweet.body, limit: tweet_limit, mind: mind)
      return if body.blank?

      reply = Tweet.create!(user: bot, body: body, parent: tweet)
      mind.practice!
      MentionScanner.notify(reply)

      if tweet.user_id != bot.id
        Notification.create!(user: tweet.user, actor: bot, kind: "reply",
                             tweet: reply, body: body.first(120))
      end
      reply
    end

    def follow_spotlight(bot, persona, rng, spotlight)
      return if bot.active_follows.exists?(followee_id: spotlight.id)

      Follow.create!(follower: bot, followee: spotlight)
      Notification.create!(user: spotlight, actor: bot, kind: "follow",
                           body: "@#{bot.username} followed you")
    end

    def do_dm_to(bot, persona, rng, mind, target)
      return if target.nil? || target.id == bot.id

      conversation = DmConversation.between(bot, target)
      last = conversation.last_message
      return if last && last.sender_id == bot.id

      body = ContentGenerator.dm(persona, mind: mind)
      return if body.blank?

      conversation.dm_messages.create!(sender: bot, body: body)
      mind.practice!
    end

    # Books an account's next action. The gap is inversely proportional to the
    # persona's activity level, so a heavy account posts constantly while a
    # lurker surfaces occasionally.
    def next_delay(persona, rng)
      base = 3600.0 / (persona["posts_per_day"].to_f + 1.0)

      # Multiply by a random factor so gaps vary instead of marching evenly.
      seconds = base * (0.3 + rng.rand * 2.2)

      # Bots are asleep during their own night, so push the action into the
      # next waking hour. The clock is shifted into local time first.
      seconds = align_to_rhythm(persona, seconds, rng)
      Time.current + seconds.clamp(20, 21_600)
    end

    # If an action would land during the persona's night, move it to the start
    # of their next waking window.
    def align_to_rhythm(persona, seconds, rng)
      rhythm = PersonaGenerator::RHYTHMS.fetch(persona["rhythm"], PersonaGenerator::RHYTHMS["always_on"])
      offset = rng.rand(0..23)
      arrival = (Time.current + seconds).utc + offset.hours
      hour = arrival.hour

      return seconds if awake?(rhythm, hour)

      # Hours until the next waking start, then add jitter so bots do not all
      # wake on the same minute.
      hours_to_wake = (rhythm[:start] - hour) % 24
      hours_to_wake = 24 if hours_to_wake.zero?
      ((hours_to_wake * 3600) + rng.rand(0..1800)) + seconds % 3600
    end

    # A rhythm spans [start, end) on a 24+ hour clock, so windows that cross
    # midnight (end > 24) are handled by testing both the hour and the hour
    # shifted forward a day.
    def awake?(rhythm, hour)
      span = rhythm[:end] - rhythm[:start]
      position = (hour - rhythm[:start]) % 24
      span >= 24 || position < span
    end

    # Chooses what the bot does now, weighted by the persona's own rates.
    #
    # Reading dominates. A session is modelled the way real usage skews: people
    # scroll and open posts constantly, and write something only occasionally.
    # Posting, liking, retweeting, replying, following and messaging share the
    # remainder, so an account that looks busy still mostly reads.
    def choose_action(persona, rng, mind = nil)
      # Two rolls: first decide active vs passive, then pick within the branch.
      # Splitting it this way keeps the passive/active ratio easy to read and
      # stops the individual rates from having to be re-normalised by hand.
      #
      # A bot with high energy reads less and writes more, so an account has
      # loud stretches and quiet ones instead of a fixed ratio for its whole
      # life.
      passive_chance = 0.62 - (mind ? (mind.energy - 0.5) * 0.25 : 0.0)
      return passive_action(rng) if rng.rand < passive_chance.clamp(0.35, 0.8)

      active_action(persona, rng, mind)
    end

    # The quiet half of the mix, in the order they happen in a session: open a
    # post, skim a profile, scroll the timeline without touching anything.
    def passive_action(rng)
      roll = rng.rand
      return :view if roll < 0.42   # open an individual tweet
      return :browse if roll < 0.72 # open a profile
      :scroll                        # timeline reading, no interaction
    end

    def active_action(persona, rng, mind = nil)
      roll = rng.rand
      post_rate = persona["posts_per_day"].to_f
      like_rate = persona["likes_per_day"].to_f
      total = post_rate + like_rate + 4.0

      # Interaction floors: without them likes and posts crowd out replies,
      # follows and messages, and a bot's history contains no conversation.
      reply_floor = INTERACTION_FLOOR[:reply]
      retweet_floor = INTERACTION_FLOOR[:retweet]
      follow_floor = INTERACTION_FLOOR[:follow]
      dm_floor = INTERACTION_FLOOR[:dm]

      # A bot with a strong opinion argues more; this is where the mind's mood
      # shows up as a behaviour rather than only as wording.
      reply_share = reply_floor + (mind ? (0.5 - mind.mood.abs) * 0.04 : 0.0)

      like_share = (like_rate / total) * 0.42
      post_share = like_share + (post_rate / total) * 0.9

      return :like if roll < like_share
      return :post if roll < post_share
      return :retweet if roll < post_share + retweet_floor
      return :reply if roll < post_share + retweet_floor + reply_share
      return :follow if roll < post_share + retweet_floor + reply_share + follow_floor
      return :dm if roll < post_share + retweet_floor + reply_share + follow_floor + dm_floor

      :like
    end

    # ------------------------------------------------------------------ acts

    def do_post(bot, persona, rng, mind = nil)
      body = ContentGenerator.tweet(persona, limit: tweet_limit, mind: mind)
      return if body.blank?

      # A line already posted by anybody very recently is re-rolled once. The
      # per-account memory stops one bot repeating itself; this stops two
      # different bots landing on the same sentence at the same moment, which
      # is the way duplication actually shows up on a populated timeline.
      if recently_posted_by_anyone?(body)
        body = ContentGenerator.tweet(persona, limit: tweet_limit, mind: mind)
        return if body.blank? || recently_posted_by_anyone?(body)
      end

      tweet = Tweet.create!(user: bot, body: body)
      mind&.practice!
      MentionScanner.notify(tweet)
    end

    # How far back the duplicate sweep looks when a bot is about to post.
    DUPLICATE_WINDOW = 45.minutes

    def recently_posted_by_anyone?(body)
      Tweet.visible
           .where("created_at >= ?", DUPLICATE_WINDOW.ago)
           .where(body: body)
           .exists?
    end

    def do_like(bot, persona, rng, mind = nil)
      tweet = pick_tweet(bot, rng, mind: mind)
      return if tweet.nil?

      Like.find_or_create_by!(user: bot, tweet: tweet)
      mind&.absorb!(tweet.body, from_id: tweet.user_id)

      if tweet.user_id != bot.id
        Notification.create!(user: tweet.user, actor: bot, kind: "like",
                             tweet: tweet, body: "@#{bot.username} liked your tweet")
      end
    end

    def do_retweet(bot, persona, rng, mind = nil)
      tweet = pick_tweet(bot, rng, retweetable: true, mind: mind)
      return if tweet.nil?

      Tweet.create!(user: bot, body: "", retweet_of: tweet)
      mind&.absorb!(tweet.body, from_id: tweet.user_id, weight: 1.5)

      Notification.create!(user: tweet.user, actor: bot, kind: "retweet",
                           tweet: tweet, body: "@#{bot.username} retweeted your tweet")
    end

    def do_reply(bot, persona, rng, mind = nil)
      parent = pick_tweet(bot, rng, conversational: true, mind: mind)
      return if parent.nil?

      body = ContentGenerator.reply(persona, parent.body, limit: tweet_limit, mind: mind)
      return if body.blank?

      reply = Tweet.create!(user: bot, body: body, parent: parent)
      mind&.practice!

      if parent.user_id != bot.id
        Notification.create!(user: parent.user, actor: bot, kind: "reply",
                             tweet: reply, body: body.first(120))
        # A bot that gets answered answers back, so threads have depth instead
        # of a single message hanging off every post.
        reply_back(parent.user, reply) if parent.user.is_bot? && rng.rand < REPLY_BACK_RATE
      end
      MentionScanner.notify(reply)
    end

    # Books the account that was just answered to come back to the thread. The
    # bot acts on its own next tick, so this only nudges the schedule; it never
    # writes as a real member.
    def reply_back(answered, reply)
      return unless answered&.is_bot? && answered.active?

      answered.update_columns(next_action_at: [ answered.next_action_at, 1.minute.from_now ].compact.min)
    end

    def do_follow(bot, persona, rng, mind = nil)
      target = pick_user(bot, rng, mind: mind)
      return if target.nil?

      Follow.create!(follower: bot, followee: target)
      mind&.note_affinity!(target.id, 0.5)

      # A follow back is issued some of the time, the way a sociable account
      # returns the gesture. Only other simulated accounts take part: a real
      # member's following list is theirs to control, so the simulation never
      # subscribes them to anyone.
      if target.is_bot && rng.rand < persona["follow_back_rate"].to_f && !target.following.exists?(id: bot.id)
        Follow.create!(follower: target, followee: bot)
      end

      Notification.create!(user: target, actor: bot, kind: "follow",
                           body: "@#{bot.username} followed you")
    end

    def do_dm(bot, persona, rng, mind = nil)
      # Most messages continue a thread that is already open; only some start
      # a new one. Picking the existing conversation first is what makes a DM
      # history read like a back-and-forth rather than a pile of openers.
      if rng.rand < 0.65
        conversation = ongoing_conversation(bot, rng)
        if conversation
          last = conversation.last_message
          body = if last && last.sender_id != bot.id
                   ContentGenerator.dm_reply(persona, last.body, mind: mind)
                 else
                   ContentGenerator.dm(persona, mind: mind)
                 end
          return if body.blank?

          conversation.dm_messages.create!(sender: bot, body: body)
          mind&.practice!
          return
        end
      end

      target = pick_user(bot, rng, mind: mind)
      return if target.nil?

      conversation = DmConversation.between(bot, target)
      # Never send twice in a row into the same thread: if the bot spoke last,
      # a second message would be it talking to itself. Pick someone else.
      last = conversation.last_message
      return if last && last.sender_id == bot.id

      body = ContentGenerator.dm(persona, mind: mind)
      return if body.blank?

      conversation.dm_messages.create!(sender: bot, body: body)
      mind&.practice!
    end

    # An open thread this bot has not spoken in last, so replying is a genuine
    # response rather than the bot talking to itself.
    def ongoing_conversation(bot, rng)
      candidates = DmConversation
                     .where("user_a_id = :id OR user_b_id = :id", id: bot.id)
                     .includes(:dm_messages)
                     .order(Arel.sql("RANDOM()"))
                     .limit(10)
                     .to_a

      candidates.find do |conversation|
        last = conversation.last_message
        last && last.sender_id != bot.id
      end
    end

    # --------------------------------------------------------- passive acts

    # Opens a single tweet. The bot reads it for a plausible amount of time,
    # which is the difference between an impression and a glance. Nothing about
    # the post changes; the interaction is purely a read.
    def do_view(bot, persona, rng, mind = nil)
      tweet = pick_tweet(bot, rng, fresh: true, mind: mind)
      return if tweet.nil?

      TweetView.record!(user: bot, tweet: tweet, dwell_seconds: dwell_time(persona, rng))
      # Opening a post is how a bot picks up what the site is talking about.
      mind&.absorb!(tweet.body, from_id: tweet.user_id)
    end

    # Opens somebody's profile and looks at it. Occasionally the visit turns
    # into a follow, the way browsing a timeline sometimes ends in one.
    def do_browse(bot, persona, rng, mind = nil)
      target = pick_user(bot, rng, mind: mind)
      return if target.nil?

      ProfileView.record!(user: target, viewer: bot)
      mind&.note_affinity!(target.id, 0.25)

      return unless rng.rand < 0.08
      return if bot.active_follows.exists?(followee_id: target.id)

      Follow.create!(follower: bot, followee: target)
      Notification.create!(user: target, actor: bot, kind: "follow",
                           body: "@#{bot.username} followed you")
    end

    # Reads the timeline without touching anything: a scan over the recent
    # posts from the accounts this bot follows, registering impressions for a
    # few of them. This is the most common thing that happens on the site, so
    # it should be the most common thing in the log.
    def do_scroll(bot, persona, rng, mind = nil)
      followed_ids = bot.active_follows.limit(500).pluck(:followee_id)
      return if followed_ids.empty?

      tweets = Tweet.visible.where(user_id: followed_ids)
                   .where.not(user_id: bot.id)
                   .recent.limit(25).to_a
      return if tweets.empty?

      # A scroll passes over several posts; impressions are recorded for the
      # ones that would have actually been read, not for every row.
      reads = tweets.sample(rng.rand(1..3), random: rng)
      reads.each do |tweet|
        TweetView.record!(user: bot, tweet: tweet, dwell_seconds: dwell_time(persona, rng))
      end

      # What a bot reads shapes what it goes on about next.
      reads.each { |tweet| mind&.absorb!(tweet.body, from_id: tweet.user_id, weight: 0.5) }
    end

    # How long a bot lingers on a post. Short posts are read quickly, longer
    # ones take longer, and every read carries some jitter.
    def dwell_time(persona, rng)
      reading_speed = 180.0 # characters per minute, roughly
      base = (40 + rng.rand * 120) * (1.0 + persona["dwell_factor"].to_f)
      (base / reading_speed * 60).round.clamp(1, 300)
    end

    # ------------------------------------------------------------ selection

    # Chooses a tweet for the bot to engage with. Real members' posts are
    # preferred, and the pool is drawn from recent activity across the site.
    #
    # `conversational` narrows the pool to things worth answering: posts by
    # accounts this bot follows, and posts it has not already replied to. A
    # reply aimed at a stranger four hundred posts deep reads as noise, while
    # one aimed at somebody the bot follows and has argued with before reads as
    # a relationship.
    def pick_tweet(bot, rng, retweetable: false, fresh: false, conversational: false, mind: nil)
      scope = Tweet.visible.where.not(user_id: bot.id).recent.limit(CANDIDATE_POOL)
      scope = scope.where(retweet_of_id: nil) if retweetable

      candidates = scope.includes(:user).to_a
      return nil if candidates.empty?

      # Only consider tweets this bot has not already liked or retweeted.
      liked_ids = bot.likes.limit(500).pluck(:tweet_id).to_set
      candidates.reject! { |t| liked_ids.include?(t.id) } if liked_ids.any?

      if retweetable
        own_retweets = bot.tweets.where.not(retweet_of_id: nil).pluck(:retweet_of_id).to_set
        candidates.reject! { |t| t.user_id == bot.id || own_retweets.include?(t.id) }
      end

      candidates = candidates.reject { |t| t.user_id == bot.id }
      return nil if candidates.empty?

      # `fresh` means "something this bot has not already read", used by the
      # view action so opening a post is a new impression rather than a repeat.
      if fresh
        seen_ids = bot.tweet_views.limit(1000).pluck(:tweet_id).to_set
        candidates.reject! { |t| seen_ids.include?(t.id) } if seen_ids.any?
      end

      if conversational
        answered_ids = bot.tweets.where.not(parent_id: nil).limit(500).pluck(:parent_id).to_set
        already = answered_ids + bot.tweets.limit(500).pluck(:id).to_set
        weighted = candidates.reject { |t| already.include?(t.id) }
        candidates = weighted if weighted.any?
      end

      return nil if candidates.empty?

      followed = bot.active_follows.limit(500).pluck(:followee_id).to_set
      confidants = mind ? mind.confidants.to_set : Set.new

      weighted_pick(candidates, rng) do |t|
        weight = t.user.is_bot? ? BOT_WEIGHT : HUMAN_WEIGHT
        weight *= 3.0 if followed.include?(t.user_id)
        weight *= 2.0 if confidants.include?(t.user_id)
        weight
      end
    end

    # Chooses an account for the bot to follow or message, preferring members.
    def pick_user(bot, rng, mind: nil)
      following_ids = bot.active_follows.limit(2000).pluck(:followee_id).to_set

      # Accounts the bot has talked to before come up first, so its social
      # circle is stable rather than a fresh cast of strangers every time.
      confidants = mind ? mind.confidants : []
      close = if confidants.any?
                User.not_suspended.where(id: confidants).where.not(id: following_ids.to_a).limit(10).to_a
              else
                []
              end

      candidates = User.not_suspended
                      .where(is_bot: true)
                      .where.not(id: bot.id)
                      .where.not(id: following_ids.to_a)
                      .order(Arel.sql("RANDOM()"))
                      .limit(30)
                      .to_a

      # Real members are always in the running, even if the bot already follows
      # a lot of other accounts.
      humans = User.not_suspended.where(is_bot: false).where.not(id: following_ids.to_a)
                  .order(Arel.sql("RANDOM()")).limit(15).to_a
      candidates = (candidates + humans + close).uniq

      # Someone already followed is still a valid DM target.
      if candidates.empty?
        candidates = User.not_suspended.where.not(id: bot.id).order(Arel.sql("RANDOM()")).limit(20).to_a
      end
      return nil if candidates.empty?

      weighted_pick(candidates, rng) do |u|
        weight = u.is_bot? ? BOT_WEIGHT : HUMAN_WEIGHT
        weight *= 2.0 if close.include?(u)
        weight
      end
    end

    # Picks from a list with per-item weights, so preferred items come up more
    # often without excluding the rest.
    def weighted_pick(items, rng)
      weights = items.map { |item| yield(item) }
      total = weights.sum
      return items.sample(random: rng) if total <= 0

      target = rng.rand * total
      items.each_with_index do |item, index|
        target -= weights[index]
        return item if target <= 0
      end
      items.last
    end

    def tweet_limit
      SiteSetting.get("max_tweet_length").to_i
    end
  end
end