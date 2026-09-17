# Turns a mind into sentences.
#
# The previous version filled fixed templates with a topic, which is why bots
# read as a word bank being reshuffled: the *shape* of every post came from a
# list, so two accounts with different views produced the same sentences with
# different nouns. This version writes from the inside out.
#
# A post is assembled from four parts, in order:
#
#   thought    what the account believes about the subject, and why
#   evidence   what it noticed that makes the thought worth saying now
#   relation   how the subject connects to the account's own life
#   stance     a hedge, a challenge, or a call to action, when the mood is
#              strong enough to add one
#
# The vocabulary for each part is grouped by *the kind of claim it makes*, not
# by topic. A comparison needs a comparison phrase; a prediction needs a future
# phrase. The subject supplies the noun, the belief supplies the direction, and
# the reason supplies the argument, so the same machinery produces "the
# refactor pays you back for the time it takes" for one developer and "other
# things in the same space are better than the refactor" for another.
module Composer
  # ---------------------------------------------------------------- lexicon

  # Openers that frame a claim. These are deliberately topic-free: they say how
  # the account is about to argue, not what it is arguing about.
  FRAMING = {
    plain: [ "", "", "", "genuinely, ", "honestly, " ],
    hedged: [ "look, ", "not sure I'm right about this but ", "might be alone here, but " ],
    insistent: [ "I'll say it again: ", "saying this once more: ", "for the record: " ],
    wondering: [ "been thinking about this a lot - ", "keep coming back to this - ", "still turning it over: " ]
  }.freeze

  # Evidence: what the account has actually observed, which is what makes a
  # claim concrete rather than a bare assertion.
  EVIDENCE = [
    "I've been paying closer attention than I used to",
    "spent the last few weeks properly in it",
    "watched what everyone else does with it",
    "went back to it after a long break",
    "compared notes with someone who lives and breathes it",
    "had a run of days where it was all I did",
    "gave it a fair go rather than judging from the outside",
    "been on both sides of this one now"
  ].freeze

  # How the subject connects to the account's own habits, so a claim is
  # situated in a life rather than floating free. Each is written to stand
  # alone after a dash, so no connective surgery is needed when it is attached.
  RELATION = [
    "it has taken over most of my evenings",
    "not how I expected to spend my week",
    "cheaper than the alternatives, at least",
    "it keeps finding its way into my day",
    "it is the part I look forward to now",
    "I would not have said that a year ago",
    "my week has rearranged itself around it"
  ].freeze

  # A closing challenge, used when the account feels strongly.
  CHALLENGE = [
    "try to change my mind on this",
    "I'll hear the other side but I doubt it",
    "happy to be proved wrong, genuinely",
    "and I don't think that's controversial"
  ].freeze

  # Softeners for an account that is not sure yet.
  HEDGE = [
    "I think, anyway",
    "might be talking nonsense",
    "ask me again next week",
    "early impressions though",
    "could be wrong about this one"
  ].freeze

  # Openings that set the scene before a claim, chosen by mood.
  LOW_OPENINGS = [
    "tired of pretending about this",
    "there is a limit and I have reached it",
    "long week",
    "not in the mood to be talked round",
    "quiet grumble"
  ].freeze

  HIGH_OPENINGS = [
    "good news everyone",
    "I need everyone to hear this",
    "genuinely delighted about this",
    "small joy for the day",
    "this is a good one"
  ].freeze

  # Questions an account asks when it is genuinely unsure, which is distinct
  # from a rhetorical question used to start a rant.
  CURIOUS_QUESTIONS = [
    "is this a me problem or a general one",
    "am I doing this badly or is it just like this",
    "has anyone made this work for them",
    "what am I missing here",
    "is it worth the effort or am I chasing nothing",
    "does anyone else find this endlessly fiddly",
    "where would you start with it"
  ].freeze

  # Self-directed remarks, for an account thinking out loud rather than
  # addressing an audience.
  ASIDES = [
    "note to self",
    "reminder for later",
    "logging this for my own benefit",
    "putting a pin in this"
  ].freeze

  # ------------------------------------------------------------- agreement

  # The verb a subject takes in the present tense, so "cats are" and "coffee
  # is" both come out right and a subject picked up from free text still
  # agrees with its sentence.
  def self.copula(topic)
    TopicSpace.agreement(topic) == :plural ? "are" : "is"
  end

  def self.verb(topic, singular:, plural:)
    TopicSpace.agreement(topic) == :plural ? plural : singular
  end

  # ------------------------------------------------------------- the composition

  # Writes a standalone post about whatever the account currently has in mind.
  # `mind` may be nil, in which case the persona's interests carry the subject
  # and the account has no particular view - used only by the bulk seeder,
  # which runs before any mind has formed.
  def self.post(persona, mind: nil, rng: Random.new)
    topic = mind ? mind.active_subject : Array(persona["interests"]).sample(random: rng)
    topic = Array(persona["interests"]).sample(random: rng) if topic.blank?
    return "" if topic.blank?

    return free_thought(persona, rng) if mind.nil?

    body = argument(mind, topic, rng)
    body = "" if body.blank?
    body
  end

  # The account's actual argument about a subject: what it thinks and why,
  # optionally tied to what it has observed and how it affects its own life.
  #
  # Every clause is built around the same subject, which is why `topic` is
  # passed down rather than re-read from the mind inside each helper: a post
  # that opens about the commute and closes about cats is the tell of a
  # generator, not a person.
  def self.argument(mind, topic, rng)
    position = mind.opinion_on(topic).to_f
    strength = mind.strength_of(topic)
    reason = mind.reasoning_for(topic, rng)

    clauses = []
    opening = opening(mind, strength, rng)
    clauses << "#{opening}." if opening.present?
    clauses << sentence(grounded_claim(reason, mind, topic, rng))
    clauses << sentence(EVIDENCE.sample(random: rng)) if rng.rand < 0.35

    # A relation is a trailing aside, so it attaches with a dash to whatever
    # came before it. It keeps its own capital because the dash starts a new
    # clause, and is terminated so the next clause does not run into it.
    if rng.rand < 0.25
      clauses << "— #{sentence(RELATION.sample(random: rng))}"
    end

    clauses << sentence(closing(position, strength, rng)) if rng.rand < closing_rate(strength)

    body = clauses.reject(&:blank?).join(" ")

    # A claim with nothing under it reads as a fragment, so give a short body
    # the missing context rather than naming the subject and stopping there.
    if body.length < 45
      body = "#{body} #{sentence(EVIDENCE.sample(random: rng))}"
    end
    body
  end

  # Capitalises and terminates a clause that is going to stand as a sentence.
  # The templates carry no punctuation of their own, so a post made of three
  # clauses would otherwise run together into one long string of words.
  def self.sentence(text)
    text = text.to_s.strip
    return "" if text.blank?

    text = text[0].upcase + text[1..]
    text.match?(/[.!?]\z/) ? text : "#{text}."
  end

  def self.grounded_claim(reason, mind, _topic, rng)
    framing = framing_for(mind, rng)
    prefix = FRAMING.fetch(framing, FRAMING[:plain]).sample(random: rng)
    prefix.blank? ? reason : "#{prefix}#{lower_first(reason)}"
  end

  # Only the opening letter is lowered: doing it to the whole clause would
  # mangle proper nouns. A standalone "I" is left alone, because "i have tried"
  # reads as a typo rather than as a lowered sentence opening.
  def self.lower_first(text)
    text.to_s.sub(/\AI(?=\s)/) { "I" }.sub(/\A[A-HJ-Z]/, &:downcase)
  end

  def self.framing_for(mind, rng)
    strength = mind.strength_of(mind.active_subject)
    case strength
    when :undecided then rng.rand < 0.6 ? :hedged : :wondering
    when :hostile, :committed then rng.rand < 0.35 ? :insistent : :plain
    else rng.rand < 0.3 ? :wondering : :plain
    end
  end

  def self.opening(mind, strength, rng)
    if mind.mood < -0.3
      LOW_OPENINGS.sample(random: rng)
    elsif mind.mood > 0.3
      HIGH_OPENINGS.sample(random: rng)
    end
  end

  def self.closing(position, strength, rng)
    case strength
    when :hostile, :committed then CHALLENGE.sample(random: rng)
    when :undecided then HEDGE.sample(random: rng)
    else
      position.abs > 0.35 ? HEDGE.sample(random: rng) : nil
    end
  end

  def self.closing_rate(strength)
    case strength
    when :undecided then 0.35
    when :hostile, :committed then 0.3
    else 0.2
    end
  end

  # An account with no mind yet still has to say something plausible. These are
  # observations rather than opinions, which is what somebody with no formed
  # view would actually post.
  def self.free_thought(persona, rng)
    topic = Array(persona["interests"]).sample(random: rng)
    return "#{ASIDES.sample(random: rng)}, that's a good one" if topic.blank?

    case rng.rand(4)
    when 0 then "#{TopicSpace.with_article(topic)} again - #{verb(topic, singular: 'it gets', plural: 'they get')} me every time"
    when 1 then "spending the evening on #{topic}, as usual"
    when 2 then CURIOUS_QUESTIONS.sample(random: rng)
    else "#{ASIDES.sample(random: rng)}: #{topic}"
    end
  end

  # ---------------------------------------------------------------- replies

  # Answers a specific post. The reply has to take up what the parent actually
  # said: if it asked something, answer it; if it made a claim, agree, disagree
  # or build on it according to what this account believes about the subject.
  def self.reply(persona, parent_body, mind: nil, rng: Random.new)
    topic = BotMind.extract_topic(parent_body)
    topic = Array(persona["interests"]).sample(random: rng) if topic.blank?
    return "" if topic.blank?

    subject = TopicSpace.with_article(topic)
    question = parent_body.to_s.include?("?")

    if question
      answer(topic, subject, mind, rng)
    else
      response(topic, subject, mind, rng)
    end
  end

  # Answering a question: engage with what was asked rather than restating an
  # opinion the other person did not ask for.
  def self.answer(topic, subject, mind, rng)
    position = mind ? mind.opinion_on(topic).to_f : 0.0
    committed = position.abs > 0.4

    case rng.rand(6)
    when 0..1
      committed ? "yes, #{subject} - I'd start there and not overthink it" \
                : "honestly not sure, #{subject} depends on what you want from it"
    when 2..3
      "for #{topic} I'd go with whatever you'll actually stick at"
    when 4
      "#{subject} worked for me, but I was already half in by then"
    else
      "depends how much time you've got - #{topic} rewards patience"
    end
  end

  # Responding to a claim. Agreement and disagreement are both arguments here,
  # not just verdicts, so the reply has a reason attached.
  def self.response(topic, subject, mind, rng)
    position = mind ? mind.opinion_on(topic).to_f : 0.0
    rub = mind ? mind.opinion_on(topic) - mind.mood * 0.2 : 0.0

    if rub > 0.25 && rng.rand < 0.7
      ["agreed on #{topic}", "yes - #{subject} #{copula(topic)} exactly the problem",
       "you're right about #{topic} and I don't say that often"].sample(random: rng)
    elsif rub < -0.25 && rng.rand < 0.7
      ["I don't know about #{topic} to be honest",
       "going to push back on #{subject} - it's not that simple",
       "#{subject} #{copula(topic)} doing a lot of work in that argument"].sample(random: rng)
    else
      ["interesting - I'd not framed #{topic} that way",
       "this is making me rethink #{topic} a bit",
       "fair on #{topic}, hadn't considered it",
       "#{topic} is one of those things where everyone's mileage differs"].sample(random: rng)
    end
  end

  # ------------------------------------------------------------------- DMs

  # A first message to somebody. It opens a conversation, so it has to carry a
  # reason for writing rather than just an opinion.
  def self.dm(persona, mind: nil, rng: Random.new)
    return dm_first_contact(mind, rng) if mind.nil?

    topic = mind.active_subject
    subject = TopicSpace.with_article(topic)

    if mind.mood > 0.25
      "hey - saw your post about #{topic}. #{subject} has been on my mind too, what got you into it?"
    elsif mind.mood < -0.25
      "hi. sorry to bother you but #{topic} is driving me up the wall and you seem to know about it"
    else
      "hello! quick one about #{topic} if you've got a minute"
    end
  end

  def self.dm_first_contact(mind, rng)
    topic = mind ? mind.active_subject : "things"
    ["hey, hope you don't mind the message",
     "hi! random question for you",
     "hello - been meaning to say hello for a while"].sample(random: rng) +
      ", is #{topic} something you're still into?"
  end

  # Continues a thread. A second message has to pick up the thread's subject,
  # otherwise the conversation reads as two strangers talking past each other.
  def self.dm_reply(persona, previous_body, mind: nil, rng: Random.new)
    topic = BotMind.extract_topic(previous_body)
    question = previous_body.to_s.include?("?")

    if question
      subject = TopicSpace.with_article(topic.presence || "that")
      ["yeah #{subject} is the whole thing really",
       "good question - I've been going back and forth on #{topic}",
       "#{subject} worked out for me eventually, took a while though"].sample(random: rng)
    elsif topic.present?
      mind&.absorb!(previous_body)
      ["that matches what I found with #{topic}",
       "see, #{topic} is exactly the bit I can't work out",
       "fair - I'll give #{topic} another go this weekend"].sample(random: rng)
    else
      ["ha, that's fair", "right?", "ok that's a good point", "no worries at all"].sample(random: rng)
    end
  end
end