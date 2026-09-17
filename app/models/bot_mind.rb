# The evolving half of a simulated account.
#
# A persona is fixed at generation: archetype, interests, voice. On its own
# that produces a population where every account with the same archetype says
# the same things forever, which reads as a script rather than a person. The
# mind is the part that changes, and it is what makes two accounts with the
# same archetype drift apart over time.
#
# It holds:
#
#   mood       how the account feels right now, drifting with what happens to
#              it and pulling the wording of its posts positive or negative
#   energy     how talkative it is at the moment, so an account has loud and
#              quiet stretches instead of a flat rate
#   fixations  the handful of subjects it is currently going on about, seeded
#              from its interests and then reshuffled by what it reads
#   beliefs    a real position on each subject, with the reason attached, so
#              the account can explain itself instead of restating a feeling
#   affinity   who it has been talking to, which decides who it seeks out
#   said       fingerprints of what it recently posted, to stop it repeating
#
# Everything is stored on the user row as JSON, so the mind survives restarts
# and can grow new keys without a migration.
class BotMind
  MAX_FIXATIONS = 6
  MAX_SAID = 24
  MAX_AFFINITY = 30

  # How many subjects' mention counts to remember. Beyond this the least-seen
  # subjects are dropped; a subject that matters will come round again.
  MAX_SEEN = 60

  # Guards against a mind that somehow never converges on a subject.
  FIXATION_POOL = 5

  attr_reader :data

  def self.load(user)
    raw = user.respond_to?(:mind) ? user.mind : nil
    parsed = begin
      JSON.parse(raw.presence || "{}")
    rescue JSON::ParserError
      {}
    end
    new(user, parsed.is_a?(Hash) ? parsed : {})
  end

  def initialize(user, data = {})
    @user = user
    @data = data || {}
    seed_from_persona
  end

  def to_json_for_storage
    @data.to_json
  end

  def save
    return unless @user.respond_to?(:mind=)

    # `update_columns` skips callbacks and validations, which is what we want:
    # the mind changes on every action and must not run the whole user
    # validation stack or bump the row's timestamps.
    @user.update_columns(mind: to_json_for_storage)
    self
  end

  # ------------------------------------------------------------- accessors

  def mood
    @data["mood"].to_f.clamp(-1.0, 1.0)
  end

  def mood=(value)
    @data["mood"] = value.to_f.clamp(-1.0, 1.0).round(3)
  end

  def energy
    @data.fetch("energy", 0.5).to_f.clamp(0.05, 1.0)
  end

  def energy=(value)
    @data["energy"] = value.to_f.clamp(0.05, 1.0).round(3)
  end

  def fixations
    @data["fixations"] ||= []
  end

  # Beliefs are stored richer than the old flat opinions: each carries the
  # reasoning behind it. `opinions` is kept as the score view so existing
  # callers that only need a number keep working.
  def beliefs
    @data["beliefs"] ||= {}
  end

  def opinions
    @data["opinions"] ||= {}
  end

  # A subject the account has been thinking about, with the reason it settled
  # on. The subject's own interests start out informed by the archetype, so a
  # developer begins with a view on deploys rather than a coin flip.
  def belief_on(topic)
    key = normalize_topic(topic)
    record = beliefs[key] ||= form_belief(key)
    record
  end

  # The numeric stance, read from the belief when one exists so the two views
  # can never disagree.
  def opinion_on(topic)
    key = normalize_topic(topic)
    return belief_on(key)["position"].to_f if beliefs.key?(key)

    opinions[key] ||= (rand * 2 - 1).round(2)
  end

  def nudge_opinion!(topic, delta)
    key = normalize_topic(topic)
    record = belief_on(key)
    before = record["position"].to_f
    record["position"] = (before + delta).clamp(-1.0, 1.0).round(2)

    # Crossing zero is a change of mind, and a change of mind deserves a new
    # reason: keeping the old one would make the account explain a position it
    # no longer holds.
    if before.sign != record["position"].sign
      record["basis"] = Belief.pick_basis(Random.new(hash_seed(key)))
      record["formed_at"] = ticks
    end
    record
  end

  # The reason this account holds its position, as a sentence. This is what
  # turns "coffee is great" into a statement with an argument behind it.
  def reasoning_for(topic, rng = Random.new)
    record = belief_on(topic)
    Belief.ground_for(record["position"].to_f, record["basis"].to_sym, topic, rng)
  end

  def strength_of(topic)
    Belief.strength(belief_on(topic)["position"].to_f)
  end

  # An account with a weak or muddled position hedges; a committed one does
  # not. Callers use this to decide whether to add a qualifier.
  def hedge_rate(topic)
    Belief.hedge(strength_of(topic))
  end

  def affinity
    @data["affinity"] ||= {}
  end

  def said
    @data["said"] ||= []
  end

  def ticks
    @data["ticks"].to_i
  end

  # How practised the account is at talking. It rises with the number of things
  # the account has actually said, and falls back a little whenever it has been
  # quiet too long, which is what makes a prolific account read as more
  # fluent - fewer dropped letters, tidier sentences - than a lurker.
  def proficiency
    base = @data.fetch("proficiency", 0.0).to_f
    base.clamp(0.0, 1.0)
  end

  def proficiency=(value)
    @data["proficiency"] = value.to_f.clamp(0.0, 1.0).round(4)
  end

  # Called every time the account puts words in public. Speech makes the
  # account better at speech, with sharply diminishing returns so it does not
  # become a perfect typist after a dozen tweets.
  def practice!
    gain = (1.0 - proficiency) * 0.12
    self.proficiency = proficiency + gain
    @data["utterances"] = @data.fetch("utterances", 0).to_i + 1
    self
  end

  def utterances
    @data.fetch("utterances", 0).to_i
  end

  # How much this account is still finding its voice, 1.0 being brand new.
  def greenness
    (1.0 - proficiency).clamp(0.0, 1.0)
  end

  # ------------------------------------------------------------ the changes

  # Nudge the mind in response to something that happened. `drift` is the
  # general unsettledness: a bot with no engagement slowly flattens out and
  # then perks up when somebody answers it.
  def tick!(drift: 0.05)
    @data["ticks"] = ticks + 1
    self.mood = mood * 0.9 + (rand * 2 - 1) * drift
    self.energy = energy * 0.85 + rand * 0.25
    rotate_fixations! if rand < 0.25

    # Having read something, an account sometimes decides to come back to it
    # later rather than only reacting in the moment. It is the difference
    # between a timeline of reactions and one of preoccupations.
    if @data["active_subject"].present? && rand < 0.3
      plan_to_revisit!(@data["active_subject"])
    end
    self
  end

  def rotate_fixations!
    pool = Array(@persona_interests)
    return if pool.empty?

    # Drop one fixation and pull in a subject it has not been on about lately.
    fixations.shift if fixations.size >= MAX_FIXATIONS
    candidates = pool - fixations
    fixations << candidates.sample if candidates.any?
    fixations.compact!
    fixations.uniq!
    fixations.shift while fixations.size > MAX_FIXATIONS
    fixations
  end

  # Takes something from what the bot just read: a subject worth picking up,
  # and a note of who it was talking to.
  def absorb!(text, from_id: nil, weight: 1.0)
    topic = BotMind.extract_topic(text)
    if topic.present?
      # Reading something is what puts a subject on the account's mind, so a
      # recognised subject becomes the active one.
      @data["active_subject"] = topic

      # A fixation takes corroboration. One stray mention is a typo or a
      # passing word; only a subject the account has met more than once is
      # worth returning to, otherwise a single odd tweet hijacks the account.
      counts = seen_counts
      counts[topic] = counts.fetch(topic, 0) + 1
      if counts[topic] >= 2 && !fixations.include?(topic) && rand < 0.35
        fixations.unshift(topic)
        fixations.shift while fixations.size > MAX_FIXATIONS
      end

      # Reading a subject the account already holds a view on hardens it or
      # wears it down, the way repetition does to anyone.
      nudge_opinion!(topic, (rand * 0.12 - 0.06)) if beliefs.key?(normalize_topic(topic))
    end

    note_affinity!(from_id, weight) if from_id
    self
  end

  # How often each subject has been met, so a fixation can require more than a
  # single sighting. Trimmed with the affinity data to keep the mind small.
  def seen_counts
    @data["seen"] ||= {}
  end

  # What the account is thinking about right now: what it just read if that is
  # still recent, otherwise what it usually fixates on. This is the subject a
  # post is actually written about.
  def active_subject
    @data["active_subject"].presence || current_subject
  end

  def active_subject=(topic)
    @data["active_subject"] = normalize_topic(topic)
  end

  # A subject the account has decided to come back to. Roughly the human habit
  # of meaning to follow something up, and it is why a timeline shows the same
  # account circling a subject across a day rather than hopping at random.
  def pending_subject
    @data["pending_subject"].presence
  end

  def plan_to_revisit!(topic)
    @data["pending_subject"] = normalize_topic(topic)
  end

  def clear_revisit!
    @data.delete("pending_subject")
  end

  # A compact picture of the account's state, used to decide how a post is
  # shaped rather than what it is about.
  def disposition
    {
      mood: mood,
      energy: energy,
      subject: active_subject,
      strength: strength_of(active_subject),
      position: belief_on(active_subject)["position"].to_f
    }
  end

  def note_affinity!(user_id, weight = 1.0)
    return if user_id.nil?

    key = user_id.to_s
    affinity[key] = affinity.fetch(key, 0.0) + weight
    trim_affinity!
  end

  # The accounts this bot most wants to talk to, best first.
  def confidants
    affinity.sort_by { |_id, score| -score }.first(8).map { |id, _| id.to_i }
  end

  # Records a post so the same wording does not come back around.
  def remember!(body)
    fingerprint = BotMind.fingerprint(body)
    return if fingerprint.blank?

    said.unshift(fingerprint)
    said.slice!(MAX_SAID..)
  end

  def recently_said?(body)
    said.include?(BotMind.fingerprint(body))
  end

  # A subject to talk about now: weighted toward what the account currently
  # fixates on, with the odd wildcard so it does not loop on one thing.
  def current_subject
    return Array(@persona_interests).sample if fixations.empty?
    return Array(@persona_interests).sample if rand < 0.2

    fixations.sample
  end

  # ------------------------------------------------------------ housekeeping

  def trim_affinity!
    if affinity.size > MAX_AFFINITY
      keep = affinity.sort_by { |_id, score| -score }.first(MAX_AFFINITY).to_h
      @data["affinity"] = keep
    end

    if seen_counts.size > MAX_SEEN
      keep = seen_counts.sort_by { |_topic, count| -count }.first(MAX_SEEN).to_h
      @data["seen"] = keep
    end
  end

  def seed_from_persona
    @persona_interests = Array(@user&.persona_hash&.fetch("interests", nil))
    @data["mood"] = (rand * 1.6 - 0.8).round(3) unless @data.key?("mood")
    @data["energy"] = (0.25 + rand * 0.6).round(3) unless @data.key?("energy")

    if fixations.empty? && @persona_interests.any?
      @data["fixations"] = @persona_interests.sample([ 3, @persona_interests.size ].min)
    end

    seed_beliefs!
  end

  # An account starts with formed views on the subjects it actually cares
  # about, and none on anything else. A view on a subject it has no interest in
  # would be a view on nothing, which is exactly the hollowness the previous
  # generator produced.
  def seed_beliefs!
    archetype = @user&.persona_hash&.fetch("archetype", nil).to_s
    @persona_interests.each do |topic|
      key = normalize_topic(topic)
      next if beliefs.key?(key)

      beliefs[key] = build_belief(key, archetype)
    end
  end

  # Forms a view on a subject the account has met while reading. The position
  # is nudged toward whatever mood it is in, so a good day makes an account
  # warmer about new things and a bad day makes it colder.
  def form_belief(topic)
    key = normalize_topic(topic)
    known = @persona_interests.to_a.map { |i| normalize_topic(i) }

    position =
      if known.include?(key)
        build_belief(key, @user&.persona_hash&.fetch("archetype", nil).to_s)["position"]
      else
        # A subject it knows nothing about: a mild view, shaded by mood.
        ((rand * 0.8 - 0.4) + mood * 0.35).clamp(-1.0, 1.0).round(2)
      end

    {
      "position" => position.to_f.round(2),
      "basis" => Belief.pick_basis(Random.new(hash_seed(key) + 7)).to_s,
      "formed_at" => ticks
    }
  end

  # Built from a per-subject seed so a persona is reproducible: the same
  # account rebuilt from its seed holds the same views.
  def build_belief(topic, archetype)
    rng = Random.new(hash_seed("#{archetype}:#{topic}"))

    # The archetype tilts the starting position: a developer is disposed to be
    # positive about a refactor, a sports fan about the derby. Without this the
    # population averages out to indifference on everything.
    tilt = archetype_tilt(archetype, topic)
    position = ((rng.rand * 2 - 1) * 0.7 + tilt).clamp(-1.0, 1.0).round(2)

    {
      "position" => position,
      "basis" => Belief.pick_basis(rng).to_s,
      "formed_at" => 0
    }
  end

  # How much an archetype's interests lean one way. Small, so it shades the
  # view rather than dictating it.
  def archetype_tilt(archetype, topic)
    return 0.0 if archetype.blank?

    topics = Array(PersonaGenerator::TOPICS[archetype])
    return 0.0 if topics.empty?

    # Anything from the account's own field is more likely to be a passion than
    # a gripe, which is how the home timeline ends up looking like a place
    # where people mostly talk about what they like.
    topics.map(&:downcase).include?(normalize_topic(topic)) ? 0.25 : 0.0
  end

  def normalize_topic(topic)
    topic.to_s.strip.downcase
  end

  # A stable integer for a string, so seeded choices survive a reload. Ruby's
  # String#hash is randomised per process, so it cannot be used here.
  def hash_seed(text)
    text.to_s.each_byte.reduce(17) { |acc, byte| (acc * 31 + byte) % 2_147_483_647 }
  end

  # A short fingerprint of a body, used for the anti-repetition check. Only
  # letters matter, so punctuation and casing changes do not hide a repeat.
  def self.fingerprint(body)
    body.to_s.downcase.gsub(/[^a-z0-9 ]/, "").split.first(6).join(" ")
  end

  # A subject picked up from something the bot just read. A subject the site
  # already knows about is preferred, because that is a thing the account can
  # actually hold a view on; otherwise the most distinctive noun is taken and
  # treated as a new subject.
  def self.extract_topic(text)
    known = TopicSpace.detect(text)
    return known if known.present?

    words = text.to_s.split(/\s+/).map { |word| word.gsub(/[^A-Za-z]/, "").downcase }
    words.select! { |word| word.length > 4 && !STOPWORDS.include?(word) }
    return nil if words.empty?

    words.max_by(&:length)
  end

  STOPWORDS = %w[
    about there their thing things really genuinely actually literally
    because would could should being having doing going getting trying
    think thinks thought still just even much many very only also
    someone something anyone everything nothing never always everyone
    everybody nobody somebody myself yourself himself herself itself
    themselves ourselves people person stuff maybe guess sure okay yeah
  ].to_set.freeze
end