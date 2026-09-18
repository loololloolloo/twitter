class SiteSetting < ApplicationRecord
  # Keys mirror the ones the original database shipped with.
  DEFAULTS = {
    "site_name" => "Twitter",
    "site_tagline" => "What's happening?",
    "max_tweet_length" => "280",
    "registration_open" => "1",
    "maintenance_message" => "",
    "announcement" => ""
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

  # A short message pinned above every signed-in page. Blank means no banner.
  def self.announcement
    get("announcement").to_s.strip
  end

  def self.values
    DEFAULTS.dup
  end
end