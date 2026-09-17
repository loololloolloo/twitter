# What an account believes, and why.
#
# The previous generation had feelings (a mood score) but no reasons: a bot
# could be positive about coffee without anything in its head explaining the
# enthusiasm, so every enthusiastic line said the same thing in different
# words. A belief carries the reason with it - what the account noticed, what
# it decided, and what it expects to happen - which is what lets two accounts
# with the same opinion produce completely different sentences about it.
#
# A belief has three parts:
#
#   position   where the account stands, -1 opposed to +1 committed
#   ground     the observation the position rests on, in the account's words
#   basis      which kind of reasoning produced it (value, comparison,
#              prediction, experience, social) so further thought can extend it
#
# Beliefs are held in the mind's JSON, so nothing here touches the database.
module Belief
  # The kinds of reasoning an account can do about a subject. Each one answers
  # "why do you think that?" in a different way, which is what keeps a timeline
  # of like-minded accounts from reading as one voice.
  #
  # Wording is chosen so the subject is rarely the grammatical subject of a
  # verb, because "cats" and "coffee" need different verb forms and a template
  # cannot know which it will get. Where the subject does take a copula, the
  # `%v` slot is filled from its number, so "cats are" and "coffee is" both come
  # out right.
  BASES = {
    value: {
      positive: [
        "the time I've put into %s has paid off",
        "you get back what you put into %s",
        "there's more in %s than people give it credit for"
      ],
      negative: [
        "you give %s more than you get back",
        "the cost of %s never comes back to you",
        "the effort %s wants never comes back"
      ]
    },
    comparison: {
      positive: [
        "nothing in the same space holds up like %s",
        "nothing else does what %s does as well",
        "put %s beside the alternatives and it isn't close"
      ],
      negative: [
        "other things in the same space do it better than %s",
        "%s fares badly next to the alternatives",
        "put %s beside the competition and it isn't close the other way"
      ]
    },
    prediction: {
      positive: [
        "there is more to come from %s and I want to see it",
        "the best of %s is still in front of it",
        "%s %v only going to get better from here"
      ],
      negative: [
        "the peak of %s is already behind it",
        "the best of %s is behind it now",
        "%s %v going to disappoint anyone who waits"
      ]
    },
    experience: {
      positive: [
        "I have never once been let down by %s",
        "I keep coming back to %s and it keeps being good",
        "my own experience of %s has been consistently good"
      ],
      negative: [
        "I have tried %s properly and been let down every time",
        "my experience of %s has been one long disappointment",
        "every attempt I have made at %s has gone badly"
      ]
    },
    social: {
      positive: [
        "the people who really know %s all say the same thing",
        "everyone I trust on %s rates it highly",
        "the case for %s is stronger than the crowd admits"
      ],
      negative: [
        "the enthusiasm for %s is louder than the case for it",
        "the people defending %s have not thought it through",
        "the crowd is wrong about %s and it shows"
      ]
    }
  }.freeze

  # Verbs that carry a position somewhere new: adopting a belief about one
  # subject shades the account's stance on related ones.
  def self.for_topic(mind, topic)
    mind.belief_on(topic)
  end

  # The reason sentence for a position, filled with the subject. `rng` picks
  # among the phrasings so the same belief does not always surface identically.
  def self.ground_for(position, basis, topic, rng)
    table = BASES.fetch(basis.to_sym, BASES[:value])
    pool = position >= 0 ? table[:positive] : table[:negative]
    template = pool.sample(random: rng)

    # `%v` is the copula, filled from the subject's number; `%s` is the subject.
    copula = TopicSpace.agreement(topic) == :plural ? "are" : "is"
    format(template.gsub("%v", copula), topic)
  rescue ArgumentError
    template
  end

  # A short label for how committed the account is, used to choose between
  # hedged and flat statements.
  def self.strength(position)
    case position.to_f
    when -1.0...-0.6 then :hostile
    when -0.6...-0.2 then :sceptical
    when -0.2...0.2 then :undecided
    when 0.2...0.6 then :favourable
    else :committed
    end
  end

  # How a hedged account phrases itself: a weak position still hedges even when
  # the underlying sentence is a claim.
  def self.hedge(strength)
    case strength
    when :hostile, :committed then 0.15
    when :sceptical, :favourable then 0.45
    else 0.7
    end
  end

  # Basis names for a topic, chosen once when the belief forms so the account's
  # reasoning stays consistent as it talks about the subject.
  def self.pick_basis(rng)
    BASES.keys.sample(random: rng)
  end
end