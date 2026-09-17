# Builds a believable identity for a simulated account.
#
# There is no external model to write the copy, so humanness comes from
# combinatorics and unevenness instead of from a generator: each persona draws
# an archetype, a home city, a handful of interests, a writing voice and a
# daily rhythm, and every one of those choices changes what the account posts
# about, how it types, and when it is awake. Two accounts sharing an archetype
# still differ in vocabulary, activity level and sleep window.
#
# Everything is derived from a seeded RNG so a persona can be rebuilt from its
# seed, which keeps bot generation reproducible across runs.
module PersonaGenerator
  ARCHETYPES = {
    "enthusiast" => {
      weight: 20,
      bios: [
        "just a person who likes things a normal amount",
        "professional lurker, occasional poster",
        "here for the chaos mostly",
        "I have opinions and a lot of coffee",
        "trying to be normal on the internet, failing"
      ]
    },
    "developer" => {
      weight: 12,
      bios: [
        "writes code, breaks code, fixes code",
        "software person. mostly tabs vs spaces discourse",
        "shipping bugs to production since forever",
        "vim user (sorry)",
        "I debug for fun and profit"
      ]
    },
    "sports_fan" => {
      weight: 11,
      bios: [
        "sports ball enjoyer",
        "if it's on TV I'm watching it",
        "weekends are for the game",
        "season ticket holder, eternal optimist",
        "screaming at the TV professionally"
      ]
    },
    "foodie" => {
      weight: 10,
      bios: [
        "will travel for good food",
        "cooking is just chemistry you can eat",
        "I take photos of my dinner, deal with it",
        "always hungry",
        "amateur chef, professional eater"
      ]
    },
    "musician" => {
      weight: 9,
      bios: [
        "making noise since 2009",
        "guitar. also bad singing",
        "music is the only thing that makes sense",
        "bedroom producer",
        "vinyl collector, Spotify apologist"
      ]
    },
    "photographer" => {
      weight: 8,
      bios: [
        "chasing light",
        "mostly pictures of my city",
        "film shooter, digital realist",
        "shutterbug with too many SD cards",
        "I photograph things I find interesting"
      ]
    },
    "gamer" => {
      weight: 9,
      bios: [
        "probably playing something right now",
        "one more game, I promise",
        "backlog is out of control",
        "speedrun of my own life",
        "gg"
      ]
    },
    "student" => {
      weight: 8,
      bios: [
        "should be studying",
        "deadlines are a suggestion",
        "caffeine dependent, essay adjacent",
        "uni life, allegedly",
        "procrastinating professionally"
      ]
    },
    "journalist" => {
      weight: 5,
      bios: [
        "covering the news, always typing",
        "reporter. DMs open for tips",
        "words person",
        "byline haver",
        "news never sleeps and neither do I"
      ]
    },
    "artist" => {
      weight: 6,
      bios: [
        "drawing things badly on purpose",
        "art account, mostly",
        "paint on everything",
        "commissions open (sometimes)",
        "I make stuff and post it"
      ]
    },
    "parent" => {
      weight: 7,
      bios: [
        "just trying to keep the tiny humans alive",
        "parent, tired, caffeinated",
        "surviving on snacks and naps",
        "my kids are funnier than me",
        "living room is now a playroom"
      ]
    },
    "traveller" => {
      weight: 6,
      bios: [
        "40 countries and counting",
        "airport lounges are my living room",
        "wanderer with a backpack",
        "passport full of stamps",
        "have laptop will travel"
      ]
    },
    "pet_owner" => {
      weight: 8,
      bios: [
        "my dog runs this account",
        "cat staff member",
        "pet photos only, sorry",
        "human to a very demanding animal",
        "she's a good girl (and she knows it)"
      ]
    },
    "fitness" => {
      weight: 6,
      bios: [
        "leg day every day",
        "running from my problems literally",
        "gym rat, sometimes gym mouse",
        "strava is my diary",
        "sore but committed"
      ]
    },
    "science" => {
      weight: 4,
      bios: [
        "space is very big and that's fine",
        "reads papers for fun",
        "physics adjacent",
        "curious about everything",
        "data person"
      ]
    }
  }.freeze

  # Content themes shared across every archetype, so timelines are not neatly
  # compartmentalised by account type.
  GENERAL_TOPICS = [
    "coffee", "the weather", "music", "sport", "food", "sleep", "work",
    "cats", "dogs", "the news", "travel", "the weekend", "mondays",
    "television", "films", "books", "games", "the rain", "sunshine",
    "that playlist", "a good sandwich", "the commute", "a lie-in",
    "fresh laundry", "the kettle", "crisp mornings", "long evenings"
  ].freeze

  CITIES = [
    [ "London", "UK" ], [ "Manchester", "UK" ], [ "Glasgow", "UK" ],
    [ "Brooklyn", "New York" ], [ "Austin", "Texas" ], [ "Portland", "Oregon" ],
    [ "Seattle", "Washington" ], [ "Denver", "Colorado" ], [ "Chicago", "Illinois" ],
    [ "San Francisco", "California" ], [ "Los Angeles", "California" ],
    [ "Toronto", "Canada" ], [ "Vancouver", "Canada" ], [ "Montreal", "Canada" ],
    [ "Berlin", "Germany" ], [ "Munich", "Germany" ], [ "Amsterdam", "Netherlands" ],
    [ "Paris", "France" ], [ "Lyon", "France" ], [ "Madrid", "Spain" ],
    [ "Barcelona", "Spain" ], [ "Rome", "Italy" ], [ "Milan", "Italy" ],
    [ "Dublin", "Ireland" ], [ "Copenhagen", "Denmark" ], [ "Stockholm", "Sweden" ],
    [ "Oslo", "Norway" ], [ "Lisbon", "Portugal" ], [ "Vienna", "Austria" ],
    [ "Melbourne", "Australia" ], [ "Sydney", "Australia" ], [ "Auckland", "NZ" ],
    [ "Tokyo", "Japan" ], [ "Seoul", "Korea" ], [ "Singapore", "Singapore" ],
    [ "Mumbai", "India" ], [ "Bangalore", "India" ], [ "Nairobi", "Kenya" ],
    [ "Cape Town", "South Africa" ], [ "Lagos", "Nigeria" ], [ "Cairo", "Egypt" ],
    [ "Sao Paulo", "Brazil" ], [ "Buenos Aires", "Argentina" ], [ "Mexico City", "Mexico" ],
    [ "Chicago", "US" ], [ "Boston", "Massachusetts" ], [ "Philadelphia", "Pennsylvania" ],
    [ "Nashville", "Tennessee" ], [ "Minneapolis", "Minnesota" ], [ "Phoenix", "Arizona" ]
  ].freeze

  FIRST_NAMES = %w[
    James Mary Robert Patricia John Jennifer Michael Linda David Elizabeth
    William Barbara Richard Susan Joseph Jessica Thomas Sarah Charles Karen
    Christopher Nancy Daniel Lisa Matthew Betty Anthony Margaret Mark Sandra
    Donald Ashley Steven Kimberly Paul Emily Andrew Donna Joshua Michelle
    Kenneth Carol Kevin Amanda Brian Dorothy George Melissa Edward Deborah
    Ronald Stephanie Timothy Rebecca Jason Sharon Jeffrey Laura Ryan Cynthia
    Jacob Kathleen Gary Amy Nicholas Angela Eric Shirley Jonathan Anna
    Stephen Ruth Larry Brenda Justin Pamela Scott Nicole Brandon Katherine
    Frank Emma Benjamin Olivia Gregory Grace Samuel Chloe Alexander Zoe
    Patrick Lily Jack Hannah Dennis Ella Jerry Avery Tyler Harper Aaron Sofia
    Jose Isabella Adam Mia Henry Amelia Douglas Charlotte Peter Layla
    Ahmed Fatima Omar Aisha Chen Wei Yuki Haruto Priya Arjun Maya Noor
    Liam Nora Maya Elena Marco Julia Lukas Anya Ivan Nadia Yusuf Leila
    Hugo Camille Felix Ines Mateo Lucia Oscar Ingrid Erik Freya Jonas Ida
    Tariq Zara Kofi Amara Diego Valentina Pablo Carmen Rafael Elena
  ].freeze

  LAST_NAMES = %w[
    Smith Johnson Williams Brown Jones Garcia Miller Davis Rodriguez Martinez
    Hernandez Lopez Gonzalez Wilson Anderson Thomas Taylor Moore Jackson Martin
    Lee Perez Thompson White Harris Sanchez Clark Ramirez Lewis Robinson Walker
    Young Allen King Wright Scott Torres Nguyen Hill Flores Green Adams Nelson
    Baker Hall Rivera Campbell Mitchell Carter Roberts Gomez Phillips Evans
    Turner Diaz Parker Cruz Edwards Collins Reyes Stewart Morris Morales Murphy
    Cook Rogers Gutierrez Ortiz Morgan Cooper Peterson Bailey Reed Kelly Howard
    Ramos Kim Cox Ward Richardson Watson Brooks Chavez Wood James Bennett Gray
    Mendoza Ruiz Hughes Price Alvarez Castillo Sanders Patel Myers Long Ross
    Foster Jimenez Powell Jenkins Perry Russell Sullivan Bell Coleman Butler
    Barnes Henderson Fisher Cole Simmons Reynolds Jordan Hamilton Graham Kim
    Wallace Moreno Griffin West Cole Hayes Bryant Alexander Chen Ellis
  ].freeze

  # Writing voices. These change casing, punctuation and emoji habits so two
  # bots posting the same template do not read as the same writer.
  VOICES = {
    "casual" => { lowercase: 0.55, exclaim: 0.15, emoji: 0.20, typo: 0.03, ellipsis: 0.10 },
    "chatty" => { lowercase: 0.30, exclaim: 0.40, emoji: 0.35, typo: 0.02, ellipsis: 0.20 },
    "terse" => { lowercase: 0.40, exclaim: 0.05, emoji: 0.05, typo: 0.02, ellipsis: 0.05 },
    "proper" => { lowercase: 0.02, exclaim: 0.10, emoji: 0.05, typo: 0.01, ellipsis: 0.05 },
    "loud" => { lowercase: 0.10, exclaim: 0.70, emoji: 0.45, typo: 0.04, ellipsis: 0.10 },
    "dry" => { lowercase: 0.45, exclaim: 0.02, emoji: 0.03, typo: 0.01, ellipsis: 0.15 },
    "warm" => { lowercase: 0.20, exclaim: 0.30, emoji: 0.40, typo: 0.02, ellipsis: 0.15 }
  }.freeze

  EMOJI = %w[😀 😂 😅 🙂 😉 😍 🤔 😴 🎉 🔥 ️ 👍 👀 ✨ 😭  🤷 🌧 ☀️ ☕  🎸  🐶  📷  🚀  📚].freeze

  # Daily rhythms. A "night_owl" is awake at 3am; a "nine_to_five" is not.
  RHYTHMS = {
    "early_bird"    => { start: 5,  end: 21, peak: 7 },
    "nine_to_five"  => { start: 7,  end: 23, peak: 12 },
    "night_owl"     => { start: 11, end: 27, peak: 23 },
    "insomniac"     => { start: 6,  end: 29, peak: 2 },
    "shift_worker"  => { start: 4,  end: 24, peak: 16 },
    "always_on"     => { start: 0,  end: 24, peak: 12 }
  }.freeze

  # Archetype-specific topic vocabulary, used to build tweet bodies. Entries
  # are natural noun phrases (spaces, not hyphens) so they read correctly when
  # dropped into a sentence.
  TOPICS = {
    "developer" => [ "this deploy", "the refactor", "a regression", "typescript",
                     "python", "linux", "docker", "regex", "git", "a merge conflict",
                     "the stack trace", "unit tests", "code review", "the API",
                     "cache invalidation", "naming things", "off-by-one errors" ],
    "sports_fan" => [ "the game", "the match", "penalties", "offside", "the ref",
                      "the manager", "relegation", "the derby", "the transfer window",
                      "injury time", "VAR", "that hat-trick", "the season opener",
                      "the away end", "extra time" ],
    "foodie" => [ "sourdough", "ramen", "tacos", "espresso", "fresh pasta", "curry",
                  "brunch", "dumplings", "olive oil", "good butter", "garlic",
                  "the chilli", "leftovers", "the farmers market", "a proper roast" ],
    "musician" => [ "the new album", "the gig", "reverb", "the bassline", "the setlist",
                    "soundcheck", "vinyl", "b-sides", "the mix", "my pedals",
                    "an acoustic version", "the encore", "the bridge" ],
    "photographer" => [ "golden hour", "the light", "a wide aperture", "film grain",
                        "the frame", "35mm", "shutter speed", "portraits", "the skyline",
                        "a long exposure", "the composition" ],
    "gamer" => [ "the boss fight", "the new patch", "the speedrun", "hitboxes",
                 "the meta", "lag", "co-op", "the final level", "crafting", "RNG",
                 "the server", "a stealth section" ],
    "student" => [ "the essay", "finals", "revision", "lectures", "the deadline",
                   "the group project", "the library", "a seminar", "coursework",
                   "the footnotes", "the reading list" ],
    "journalist" => [ "the story", "the source", "the headline", "the deadline",
                      "the editors", "the brief", "the embargo", "my byline",
                      "the quote", "the follow-up" ],
    "artist" => [ "the canvas", "the palette", "ink", "layers", "the sketch",
                  "commissions", "the colour", "shading", "the outline", "the studio",
                  "a fresh sketchbook" ],
    "parent" => [ "the school run", "naptime", "the toddler", "snacks", "bedtime",
                  "the school play", "laundry", "playdates", "the pram", "sock pairs",
                  "the nursery run" ],
    "traveller" => [ "the flight", "the hostel", "a boarding pass", "jetlag",
                     "the itinerary", "passport control", "the layover", "the view",
                     "local food", "the night train", "an early start" ],
    "pet_owner" => [ "the dog", "the cat", "walkies", "treats", "the vet",
                     "belly rubs", "the park", "the fur", "hairballs", "the lead",
                     "a very good boy" ],
    "fitness" => [ "leg day", "the long run", "a PB", "my splits", "the gym",
                   "cardio", "my pace", "intervals", "the taper", "recovery",
                   "the hill repeats" ],
    "science" => [ "the paper", "the data", "the experiment", "the hypothesis",
                   "the results", "the telescope", "entropy", "the study",
                   "the model", "the sample size" ],
    "enthusiast" => GENERAL_TOPICS
  }.freeze

  def self.build(seed)
    rng = Random.new(seed)

    archetype = weighted_pick(ARCHETYPES, rng)
    rhythm = RHYTHMS.keys[rng.rand(RHYTHMS.size)]
    voice = VOICES.keys[rng.rand(VOICES.size)]
    city, region = CITIES[rng.rand(CITIES.size)]
    first = FIRST_NAMES[rng.rand(FIRST_NAMES.size)]
    last = LAST_NAMES[rng.rand(LAST_NAMES.size)]

    interests = (TOPICS.fetch(archetype, GENERAL_TOPICS) + GENERAL_TOPICS).uniq
    picks = interests.sample(rng.rand(4..7), random: rng)

    {
      "seed" => seed,
      "archetype" => archetype,
      "rhythm" => rhythm,
      "voice" => voice,
      "city" => city,
      "region" => region,
      "first_name" => first,
      "last_name" => last,
      "interests" => picks,
      "bio" => ARCHETYPES.fetch(archetype)[:bios].sample(random: rng),
      # Activity level: posts per day, and how sociable the account is. A
      # heavy account posts a lot and follows back; a lurker mostly reads,
      # likes and follows.
      "posts_per_day" => (rng.rand * 6.0 + 0.4).round(2),
      "likes_per_day" => (rng.rand * 25.0 + 3.0).round(2),
      "follow_back_rate" => (rng.rand * 0.5 + 0.35).round(2),
      "reply_rate" => (rng.rand * 0.35 + 0.08).round(2),
      "dm_rate" => (rng.rand * 0.06).round(3),
      # How long this account lingers over a post, relative to the others. A
      # reader with a high factor is a slow, thorough type; a low one skims.
      "dwell_factor" => (rng.rand * 1.6).round(2),
      # Accounts created over a long span so profiles show varied join dates.
      "account_age_days" => rng.rand(30..2400),
      "follows_at_start" => rng.rand(8..180)
    }
  end

  # Picks an archetype honouring the weights, so the population has a natural
  # mix of common and rare account types rather than a uniform spread.
  def self.weighted_pick(table, rng)
    total = table.values.sum { |entry| entry[:weight] }
    target = rng.rand * total
    table.each do |name, entry|
      target -= entry[:weight]
      return name if target <= 0
    end
    table.keys.last
  end

  # Deterministic seed for the nth generated bot.
  def self.seed_for(index)
    Digest::SHA256.hexdigest("bot-#{index}").to_i(16) % (2**31)
  end
end