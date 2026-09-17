class SiteSetting < ApplicationRecord
  # Keys mirror the ones the original database shipped with.
  DEFAULTS = {
    "site_name" => "Twitter",
    "site_tagline" => "What's happening?",
    "max_tweet_length" => "140",
    "registration_open" => "1",
    "maintenance_message" => "",
    "announcement" => "",
    "hide_bots" => "0"
  }.freeze

  validates :key, presence: true, uniqueness: true

  def self.get(key)
    value = find_by(key: key)&.value
    value.presence || DEFAULTS[key.to_s]
  end

  def self.put(key, value)
    record = find_or_initialize_by(key: key)
    record.value = value.to_s
    record.save!
    record
  end

  def self.registration_open?
    get("registration_open").to_s == "1"
  end

  # Whether the simulated population is kept out of the public timelines and
  # the people directory. Off by default, because the bots are the point of the
  # site; an operator turns it on to see the place as a real visitor would.
  def self.hide_bots?
    get("hide_bots").to_s == "1"
  end

  # A short message pinned above every signed-in page. Blank means no banner.
  def self.announcement
    get("announcement").to_s.strip
  end

  # Settings that exist so an administrator can tune the simulation without a
  # deploy. `values` lists them alongside the built-in keys so the admin screen
  # shows them even before anything has been saved.
  SIMULATION_KEYS = %w[spotlight_username followers_per_post followers_per_tick].freeze

  def self.values
    DEFAULTS.merge(
      "spotlight_username" => BotEngine::SPOTLIGHT_DEFAULT,
      "followers_per_post" => BotEngine::GROWTH_PER_POST.to_s,
      "followers_per_tick" => BotEngine::GROWTH_PER_TICK.to_s
    )
  end
end