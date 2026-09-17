# The vocabulary of subjects a simulated account can think about.
#
# The generator needs to know what a subject *is* before it can build a
# sentence around it: whether "cats" takes a plural verb, whether "coffee" is a
# mass noun that cannot be counted, and whether "the gym" is a place you go to
# rather than a thing you own. Without that, agreement and pronoun choice go
# wrong and the copy reads as assembled rather than written.
#
# Subjects also have to be recognisable inside free text, so a bot can pick up
# "the refactor" from a post it just read instead of latching onto whichever
# word happens to be longest.
module TopicSpace
  # Subjects that are grammatically plural: "cats are", not "cats is". Anything
  # a persona can care about has to agree with its verb, so the lists below are
  # backed by `classify`, which infers the answer from the word's shape when a
  # subject is met for the first time.
  KNOWN_PLURAL = %w[
    cats dogs films books games snacks treats portraits commissions lectures
    finals dumplings tacos leftovers layers hitboxes intervals hairballs
    splits pedals b-sides footnotes edits pens brushes socks dishes
    crisps chips noodles beans shoes chores errands long evenings crisp mornings
    sunny afternoons late nights early starts road trips
  ].freeze

  # Subjects that are mass nouns: no article, singular verb, no plural.
  MASS = %w[
    coffee music food sleep work sunshine rain snow cheese bread butter
    chocolate tea water wine beer sunlight fog homework revision coursework
    laundry entropy data vinyl cardio recovery lag rng crafting
  ].to_set.freeze

  # Words that end in "s" but are singular anyway. Without this, "the news"
  # would be treated as a plural and read "the news are good".
  SINGULAR_DESPITE_S = %w[
    the news the bus this that chess class glass grass stress progress
    address business darkness harness mattress access process
  ].to_set.freeze

  # Subjects that name something you do rather than something you have. These
  # take "do/go" phrasing instead of "have/own".
  ACTIVITIES = %w[
    the gym the long run leg day cardio the commute the school run naptime
    bedtime walkies revision the school play playdates the nursery run
    the morning coffee the kettle a lie-in fresh laundry the reading list
    code review unit tests the speedrun soundcheck the taper
  ].to_set.freeze

  # Subjects whose verb is "is/are" rather than something the account does to
  # them. Emotional subjects read oddly with an active verb.
  ABSTRACT = %w[
    the weather the news the weekend mondays the commute a lie-in
    the weekend vibes entropy the meta the mood the light the season opener
    the transfer window injury time relegation the deadline jetlag
    passport control the layover the view local food the night train
  ].to_set.freeze

  def self.all
    @all ||= (PersonaGenerator::TOPICS.values.flatten + PersonaGenerator::GENERAL_TOPICS).uniq.freeze
  end

  # A subject is plural when the list says so, or when its head noun is not one
  # of the "s"-ending singulars and it still looks plural.
  def self.plural?(topic)
    head = topic.to_s.downcase
    return false if SINGULAR_DESPITE_S.include?(head)
    return true if KNOWN_PLURAL.include?(head)

    # Only infer from shape for a genuine bare noun, never for a pair like
    # "sunny afternoons" that is already spelled out above.
    head.end_with?("s") && !head.end_with?("ss") && !MASS.include?(head)
  end

  def self.mass?(topic)
    MASS.include?(topic.to_s.downcase)
  end

  def self.activity?(topic)
    ACTIVITIES.include?(topic.to_s.downcase)
  end

  def self.abstract?(topic)
    ABSTRACT.include?(topic.to_s.downcase)
  end

  # Which auxiliary a subject takes in the present tense.
  def self.agreement(topic)
    plural?(topic) || mass?(topic) ? :plural : :singular
  end

  # The pronoun that stands in for a subject once it has been named.
  def self.pronoun(topic)
    plural?(topic) ? "they" : "it"
  end

  # A subject with the right article for its class: mass nouns get none,
  # plurals get none, anything starting with "the"/"a" keeps what it has, and a
  # bare count noun takes "a" or "an".
  def self.with_article(topic)
    head = topic.to_s
    return head if head.match?(/\A(the|a|an|my|this|that|some)\b/i)
    return head if mass?(head) || plural?(head)

    "#{article(head)} #{head}"
  end

  def self.article(word)
    /\A[aeiou]/i.match?(word.to_s) ? "an" : "a"
  end

  # Finds a subject the site knows about inside a piece of text, preferring the
  # longest match so "the transfer window" beats "the window". Returns nil when
  # nothing recognisable appears.
  def self.detect(text)
    haystack = text.to_s.downcase
    return nil if haystack.empty?

    all.select { |topic| haystack.include?(topic.downcase) }
       .max_by(&:length)
  end

  # Classifies a subject this module has never seen, inferring agreement from
  # its shape. Used for subjects a bot picks up from free text.
  def self.classify(topic)
    head = topic.to_s.downcase
    if plural?(head)
      :plural
    elsif mass?(head)
      :mass
    else
      :singular
    end
  end
end