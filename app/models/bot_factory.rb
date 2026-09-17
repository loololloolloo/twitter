# Creates the simulated population.
#
# Accounts are written with `insert_all` in batches rather than one `create!`
# per bot. Hashing a password costs roughly 30ms at the site's PBKDF2 settings,
# so hashing five thousand individually would take minutes; simulated accounts
# never sign in, so one precomputed digest is shared across all of them and
# sign-in for bots is refused outright (see SessionsController).
module BotFactory
  DEFAULT_COUNT = 5_000
  BATCH_SIZE = 500

  # A digest in the same format the site stores, produced once and reused.
  def self.shared_digest
    @shared_digest ||= PasswordDigest.hash(SecureRandom.hex(32))
  end

  # Number of bots currently present.
  def self.count
    User.where(is_bot: true).count
  end

  # Ensures exactly `target` bots exist, adding only what is missing. Safe to
  # call repeatedly; existing bots and everything they have done are left
  # untouched.
  def self.ensure_population(target = DEFAULT_COUNT)
    existing = count
    return 0 if existing >= target

    create(target - existing, offset: existing)
  end

  # Builds `amount` bots. `offset` keeps persona seeds stable when topping up,
  # so bot N always has the same identity.
  def self.create(amount, offset: 0, progress: nil)
    user_role = Role.find_by!(name: "user")
    now = Time.current
    made = 0

    # Every handle handed out in this run, plus every handle already in the
    # database, so a collision is resolved here rather than by silently
    # dropping a row during insert.
    taken = User.pluck(:username).to_set

    amount.times.each_slice(BATCH_SIZE) do |slice|
      rows = slice.map do |index|
        build_row(offset + index, user_role.id, now, taken)
      end

      User.insert_all(rows)
      made += rows.size
      progress&.call(made, amount)
    end

    made
  end

  def self.build_row(index, role_id, now, taken = Set.new)
    persona = PersonaGenerator.build(PersonaGenerator.seed_for(index))
    username = username_for(persona, index, taken)
    taken << username
    display_name = "#{persona['first_name']} #{persona['last_name']}"

    {
      username: username,
      display_name: display_name,
      email: "#{username}@example.com",
      password_hash: shared_digest,
      role_id: role_id,
      is_bot: true,
      persona: persona.to_json,
      bio: bio_for(persona),
      location: "#{persona['city']}, #{persona['region']}",
      # Roughly two thirds of the population gets a picture; the rest keep the
      # default avatar, as a real user base does.
      avatar_path: AvatarGenerator.generate(
        seed: persona["seed"],
        initials: AvatarGenerator.initials_for(display_name, username)
      ),
      created_at: now - persona["account_age_days"].to_i.days,
      updated_at: now - persona["account_age_days"].to_i.days,
      # Stagger the first action over the next quarter hour so a fresh
      # population ramps up within minutes instead of all waking at once. Once
      # a bot has acted its own rhythm takes over.
      next_action_at: now + (index % 900).seconds
    }
  end

  # Usernames read like handles real people choose: usually a name, sometimes
  # with a small number, occasionally a word appended. Anything already taken
  # gets digits added until it is free, which keeps handles unique without
  # exposing a long internal counter.
  def self.username_for(persona, index, taken)
    first = persona["first_name"].downcase.gsub(/[^a-z]/, "")
    last = persona["last_name"].downcase.gsub(/[^a-z]/, "")
    rng = Random.new(persona["seed"])

    base =
      case rng.rand(8)
      when 0 then "#{first}#{last}"
      when 1 then "#{first}_#{last}"
      when 2 then "#{first}.#{last}"
      when 3 then "#{first}#{last[0]}"
      when 4 then "#{first[0]}#{last}"
      when 5 then "#{first}#{rng.rand(1..99)}"
      when 6 then "#{first}#{HANDLE_WORDS.sample(random: rng)}"
      else "#{first}#{last}#{rng.rand(1..9)}"
      end

    base = sanitize_handle(base)
    candidate = base[0, 15]

    # Add digits only when needed, starting small, so most handles stay clean.
    suffix = rng.rand(1..99)
    while taken.include?(candidate)
      candidate = "#{base[0, 15 - suffix.to_s.length]}#{suffix}"
      suffix += rng.rand(1..37)
      # A pathological run could loop; fall back to the index, which is unique.
      if suffix > 100_000
        candidate = "#{base[0, 8]}#{index}"
        break
      end
    end

    candidate
  end

  def self.sanitize_handle(text)
    # Dots are stripped rather than allowed: a period in a username makes
    # /u/first.last parse as username "first" with format "last", so the
    # profile becomes unreachable. The model's USERNAME_FORMAT excludes them
    # too, and insert_all skips that validation.
    cleaned = text.gsub(/[^a-z0-9_]/, "")
    cleaned = "user#{cleaned}" if cleaned.length < 2
    cleaned
  end

  HANDLE_WORDS = %w[
    x mh uk us ny la sf ok says real irl here now
  ].freeze

  def self.bio_for(persona)
    # Only single-word interests make sensible hashtags; a phrase like
    # "a lie-in" would collapse into gibberish.
    tags = persona["interests"]
           .select { |i| i.match?(/\A[a-z]+\z/) }
           .first(3)
           .map { |i| "##{i}" }
           .join(" ")

    [ persona["bio"], "📍 #{persona['city']}", tags ].reject(&:blank?).join(" · ")[0, 160]
  end

  # Removes every simulated account and the content it produced.
  #
  # The bots are ordinary user rows, but not every table that points at a user
  # cascades on delete: conversations, message senders, notification actors and
  # audit entries have foreign keys with no `dependent:` on the model. Those are
  # cleared explicitly, in dependency order, so removing the users cannot fail
  # on a constraint.
  def self.destroy_all
    bot_ids = User.bots.pluck(:id)
    return 0 if bot_ids.empty?

    bot_tweet_ids = Tweet.where(user_id: bot_ids).pluck(:id)
    conversation_ids = DmConversation
                       .where(user_a_id: bot_ids)
                       .or(DmConversation.where(user_b_id: bot_ids))
                       .pluck(:id)

    ActiveRecord::Base.transaction do
      # Messages and conversations the bots took part in.
      DmMessage.where(sender_id: bot_ids).delete_all
      DmMessage.where(dm_conversation_id: conversation_ids).delete_all if conversation_ids.any?
      DmConversation.where(id: conversation_ids).delete_all if conversation_ids.any?

      # Notifications addressed to, sent by, or attached to a bot's content.
      Notification.where(user_id: bot_ids).delete_all
      Notification.where(actor_id: bot_ids).delete_all
      Notification.where(tweet_id: bot_tweet_ids).delete_all if bot_tweet_ids.any?

      # Audit entries are kept as a record, but no longer point at a deleted
      # account.
      AuditLog.where(actor_id: bot_ids).update_all(actor_id: nil)

      # Engagement on and by bots, then the content itself.
      Like.where(user_id: bot_ids).delete_all
      Like.where(tweet_id: bot_tweet_ids).delete_all if bot_tweet_ids.any?
      Follow.where(follower_id: bot_ids).delete_all
      Follow.where(followee_id: bot_ids).delete_all

      # Tweets left over that reference a bot tweet as their parent or source.
      Tweet.where(parent_id: bot_tweet_ids).update_all(parent_id: nil) if bot_tweet_ids.any?
      Tweet.where(retweet_of_id: bot_tweet_ids).delete_all if bot_tweet_ids.any?
      Tweet.where(user_id: bot_ids).delete_all

      Session.where(user_id: bot_ids).delete_all
      User.where(id: bot_ids).delete_all
    end

    bot_ids.size
  end
end