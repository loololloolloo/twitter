# Tasks for the simulated population.
#
#   bin/rails bots:seed            # add bots until 5,000 exist
#   bin/rails bots:seed[10000]     # grow to a specific population
#   bin/rails bots:status          # show what the population has been doing
#   bin/rails bots:run             # run the engine continuously (Ctrl-C to stop)
#   bin/rails bots:run[2.0,60]     # 2 second ticks, 60 actions per tick
#   bin/rails bots:destroy         # remove every simulated account
#   bin/rails bots:avatars         # import profile pictures for bots that lack one
#   bin/rails bots:avatars[250,dicebear]  # limit and provider can be given
#
# `bots:run` is a long-lived process that can be left running alongside the web
# server, which is how the accounts stay active around the clock.
namespace :bots do
  desc "Create simulated accounts until the target population exists (default 5000)"
  task :seed, [ :count ] => :environment do |_task, args|
    target = (args[:count].presence || BotFactory::DEFAULT_COUNT).to_i
    existing = BotFactory.count
    puts "bots present: #{existing}; target: #{target}"

    if existing >= target && !ENV["FORCE_HISTORY"]
      puts "nothing to do (set FORCE_HISTORY=1 to backfill history anyway)"
      next
    end

    started = Time.current

    if existing < target
      last_report = Time.current

      BotFactory.create(target - existing, offset: existing) do |made, total|
        next unless Time.current - last_report > 5

        elapsed = Time.current - started
        rate = (made / elapsed).round(1)
        puts "  #{made}/#{total} created (#{rate}/s)"
        last_report = Time.current
      end

      puts "created #{BotFactory.count - existing} bots in #{(Time.current - started).round(1)}s"
    end

    puts "total bots: #{BotFactory.count}"
    puts "human accounts: #{User.humans.count}"

    # History is what makes the site look established rather than freshly
    # seeded: a social graph, a backdated timeline and engagement on it.
    print "seeding follows... "
    BotSeeder.seed_follows
    puts "#{Follow.count} follows total"

    print "seeding posts... "
    BotSeeder.seed_tweets
    puts "#{Tweet.count} tweets total"

    print "seeding engagement... "
    BotSeeder.seed_engagement
    puts "#{Like.count} likes, #{Tweet.visible.where.not(retweet_of_id: nil).count} retweets"

    puts "done in #{(Time.current - started).round(1)}s"
  end

  desc "Show population size and recent simulated activity"
  task status: :environment do
    bots = BotFactory.count
    humans = User.humans.count
    due = User.bots.where("next_action_at <= ?", Time.current).count

    puts "bots:            #{bots}"
    puts "humans:          #{humans}"
    puts "due now:         #{due}"
    puts "tweets (all):    #{Tweet.visible.count} (#{Tweet.visible.where(user_id: User.bots.select(:id)).count} from bots)"
    puts "follows (all):   #{Follow.count}"
    puts "likes (all):     #{Like.count}"
    puts "retweets:        #{Tweet.visible.where.not(retweet_of_id: nil).count}"
    puts "replies:         #{Tweet.visible.where.not(parent_id: nil).count}"
    puts "dm messages:     #{DmMessage.count} in #{DmConversation.count} conversations"
    puts "notifications:   #{Notification.count}"
    puts "actions total:   #{User.bots.sum(:actions_performed)}"

    if bots.positive?
      window = 1.hour.ago
      recent = Tweet.visible.where(user_id: User.bots.select(:id)).where("created_at >= ?", window).count
      puts "bot tweets/hour: #{recent}"
      puts "busiest bots:"
      User.bots.order(actions_performed: :desc).limit(5).each do |bot|
        puts "  @#{bot.username} (#{bot.display_name}) - #{bot.actions_performed} actions, " \
             "joined #{bot.created_at.to_date}"
      end
    end
  end

  desc "Run the engine continuously; args are [interval_seconds, actions_per_tick]"
  task :run, [ :interval, :batch ] => :environment do |_task, args|
    interval = (args[:interval].presence || 2.0).to_f
    batch = (args[:batch].presence || 60).to_i

    puts "bot runner starting: tick every #{interval}s, up to #{batch} actions per tick"
    puts "population: #{BotFactory.count} bots / #{User.humans.count} humans"

    if BotFactory.count.zero?
      puts "no bots yet - run `bin/rails bots:seed` first"
      next
    end

    stop = false
    %w[INT TERM].each do |signal|
      Signal.trap(signal) { stop = true }
    end

    acts = 0
    ticks = 0

    until stop
      started = Time.current
      # A tick can raise if the database is briefly locked by a web write; the
      # loop is long-lived, so retry on the next pass instead of dying.
      begin
        acts += BotEngine.tick(count: batch)
      rescue ActiveRecord::StatementInvalid => e
        warn "tick skipped: #{e.class}"
      end
      ticks += 1

      puts "tick #{ticks}: #{acts} actions total (#{(Time.current - started).round(2)}s)" if (ticks % 30).zero?

      sleep interval
    end

    puts "stopped after #{ticks} ticks and #{acts} actions"
  end

  desc "Delete every simulated account and its content"
  task destroy: :environment do
    total = BotFactory.count
    puts "removing #{total} bots and their content..."
    BotFactory.destroy_all
    puts "bots remaining: #{BotFactory.count}"
    puts "humans kept: #{User.humans.count}"
  end

  desc "Perform one action for a single bot by username"
  task :poke, [ :username ] => :environment do |_task, args|
    bot = User.bots.find_by("username = ? COLLATE NOCASE", args[:username].to_s)
    abort "no bot named @#{args[:username]}" if bot.nil?

    BotEngine.perform(bot)
    bot.reload
    puts "@#{bot.username} acted; #{bot.actions_performed} actions so far, next at #{bot.next_action_at}"
  end

  desc "Import profile pictures from a provider for bots that have none"
  task :avatars, [ :limit, :provider, :style ] => :environment do |_task, args|
    limit = (args[:limit].presence || 500).to_i
    provider = args[:provider].presence || "dicebear"

    unless RemoteAvatar::PROVIDERS.key?(provider)
      abort "unknown provider #{provider}; choose from #{RemoteAvatar::PROVIDERS.keys.join(', ')}"
    end

    scope = User.bots.where(avatar_path: [ nil, "" ]).order(:id)
    total = scope.count
    puts "#{total} bot(s) without a picture; fetching up to #{limit} from #{provider}"

    applied = 0
    failed = 0
    scope.limit(limit).each_with_index do |bot, index|
      path = RemoteAvatar.fetch(seed: "#{bot.username}-#{bot.id}", provider: provider, style: args[:style].presence)

      if path.nil?
        failed += 1
      else
        bot.update_columns(avatar_path: path)
        applied += 1
      end

      puts "  #{index + 1}: #{applied} imported, #{failed} failed" if ((index + 1) % 25).zero?
    end

    puts "imported #{applied} picture(s); #{failed} could not be fetched"
    puts "#{User.bots.where(avatar_path: [ nil, "" ]).count} bot(s) still without a picture"
  end
end