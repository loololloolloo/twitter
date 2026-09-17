# Writes tweet text and messages for a simulated account.
#
# The words themselves come from `Composer`, which writes from the account's
# beliefs outwards. This module is the outer layer: it picks the subject, asks
# the composer to make the argument, applies the persona's voice (casing,
# punctuation, emoji, typo rate), enforces the site's length limit, and keeps
# the account from repeating itself.
#
# The split matters because voice and reasoning are independent. Two accounts
# can hold the same belief and write it in completely different registers, and
# one account can hold different beliefs and still sound like itself.
module ContentGenerator
  # Common fat-finger substitutions, applied at the persona's typo rate.
  TYPOS = {
    "the" => "teh", "and" => "adn", "you" => "yuo", "that" => "thta",
    "with" => "wiht", "have" => "hvae", "this" => "tihs", "just" => "jsut",
    "about" => "abotu", "really" => "realy", "because" => "becuase",
    "people" => "poeple", "think" => "thnik", "going" => "goign"
  }.freeze

  EMOJI = PersonaGenerator::EMOJI
  HASHTAG_WORDS = %w[
    morningcoffee mondaymotivation weekendvibes throwback tbt loveit
    nofilter goodvibes latepost sundayfunday humpday tgif selfcare
  ].freeze

  def self.tweet(persona, limit: 140, mind: nil)
    rng = Random.new
    body = compose(persona, rng, mind: mind)
    body = fit(body, limit)
    body = style(body, persona, rng, proficiency: mind&.proficiency)

    # Never hand back something the account has just said; re-roll once, then
    # fall back to a fresh subject so the timeline does not fill with echoes.
    if mind && mind.recently_said?(body)
      body = fit(compose(persona, rng, mind: mind), limit)
      body = style(body, persona, rng, proficiency: mind&.proficiency)
    end

    mind&.remember!(body)

    body
  end

  # A standalone post about whatever the account currently has in mind. The
  # reasoning comes from the mind's beliefs, so the same account writing about
  # the same subject twice says something different each time rather than
  # producing a synonym of the first post.
  def self.compose(persona, rng, mind: nil)
    Composer.post(persona, mind: mind, rng: rng)
  end

  # Writes a reply that takes up what the parent actually said. The parent's
  # subject is picked out and the account responds from its own view of it, so
  # the reply is an answer rather than a stray remark that happens to mention
  # the same noun.
  def self.reply(persona, parent_body, limit: 140, mind: nil)
    rng = Random.new
    body = Composer.reply(persona, parent_body, mind: mind, rng: rng)
    body = fit(body, limit)
    body = style(body, persona, rng, proficiency: mind&.proficiency)
    mind&.remember!(body)
    mind&.absorb!(parent_body)
    body
  end

  def self.dm(persona, limit: 500, mind: nil)
    rng = Random.new
    body = Composer.dm(persona, mind: mind, rng: rng)
    body = fit(body, limit)
    body = style(body, persona, rng, proficiency: mind&.proficiency)
    mind&.remember!(body)

    body
  end

  # A follow-up inside an existing thread. Continuing a conversation that is
  # already open is what most DMs actually are, so the copy has to react to
  # what was said rather than introduce a fresh topic.
  def self.dm_reply(persona, previous_body, limit: 500, mind: nil)
    rng = Random.new
    body = Composer.dm_reply(persona, previous_body, mind: mind, rng: rng)
    body = fit(body, limit)
    body = style(body, persona, rng, proficiency: mind&.proficiency)
    mind&.remember!(body)
    mind&.absorb!(previous_body)
    body
  end

  # Applies the persona's voice: casing, punctuation, emoji and the occasional
  # typo. These are the traits that make two accounts with the same archetype
  # still sound like different people.
  #
  # `proficiency` is how practised the account is. A fluent account keeps its
  # voice but stops making the mistakes of somebody still learning to type on
  # the internet, so the same account reads differently in year one and year
  # three rather than sounding identical for its whole life.
  def self.style(body, persona, rng, proficiency: nil)
    voice = PersonaGenerator::VOICES.fetch(persona["voice"], PersonaGenerator::VOICES["casual"])
    text = body.to_s.strip
    fluency = proficiency.nil? ? 0.0 : proficiency.to_f.clamp(0.0, 1.0)

    if rng.rand < voice[:lowercase] && !text.match?(/[A-Z]{2,}/)
      # Lowercase the first letter but leave proper-looking acronyms alone.
      text = text.sub(/\A([A-Z])/) { |m| m.downcase }
    end

    # Green accounts fat-finger more; practised ones almost never do.
    if rng.rand < voice[:typo] * (0.35 + 0.65 * (1.0 - fluency)).to_f
      word = TYPOS.keys.sample(random: rng)
      text = text.sub(/\b#{word}\b/) { TYPOS[word] }
    end

    # A practised account writes in sentences rather than trailing off.
    ellipsis_rate = voice[:ellipsis] * (0.5 + 0.5 * (1.0 - fluency)).to_f
    text = "#{text}#{'.' * rng.rand(1..3)}" if rng.rand < ellipsis_rate
    text = "#{text}!" if rng.rand < voice[:exclaim]
    text = "#{text} #{EMOJI.sample(random: rng).strip}" if rng.rand < voice[:emoji]

    # A hashtag or a mention lands on a minority of posts, as on the real
    # service, and never as the first character. Fluent accounts use fewer of
    # them, which is what a seasoned user actually looks like.
    if rng.rand < 0.12 * (1.0 - fluency * 0.5)
      text = "#{text} ##{HASHTAG_WORDS.sample(random: rng)}"
    end

    tidy_punctuation(text)
  end

  # Collapses the runs that come from stacking optional punctuation: a full
  # stop followed by an exclamation, or a stray trailing ".". Reads as a typo
  # otherwise.
  def self.tidy_punctuation(text)
    text.gsub(/([.!?])([.!?])+/) { $1 }.gsub(/\s+([,.!?])/, '\1').strip
  end

  # Trims a body to fit the site limit without cutting a word in half.
  def self.fit(text, limit)
    return text if text.length <= limit

    trimmed = text[0, limit]
    trimmed = trimmed[0, trimmed.rindex(/\s/) || limit] if trimmed.rindex(/\s/)
    trimmed = trimmed.to_s.strip

    # Truncation can leave a trailing connective or dash, which reads as a
    # sentence that was cut off rather than one that ended.
    trimmed.sub(/[\s,;:—-]+\z/, "").sub(/\b(and|but|or|the|a|to|of|with|that|it)\z/i, "").strip
  end

  def self.message(persona)
    dm(persona)
  end
end