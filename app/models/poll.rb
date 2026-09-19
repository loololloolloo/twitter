# A poll attached to a post. 2019 offered two to four choices, ran for a fixed
# span (5 minutes, 30 minutes, 1 hour, 1 day, 3 days or 1 week) and showed the
# result split once the reader had voted or the poll had closed.
class Poll < ApplicationRecord
  MIN_OPTIONS = 2
  MAX_OPTIONS = 4
  MAX_LABEL = 25

  # The durations the 2019 composer offered, in the order it listed them.
  DURATIONS = {
    "5m" => 5.minutes,
    "30m" => 30.minutes,
    "1h" => 1.hour,
    "1d" => 1.day,
    "3d" => 3.days,
    "1w" => 1.week
  }.freeze

  belongs_to :tweet
  has_many :poll_options, -> { order(:position) }, dependent: :destroy, inverse_of: :poll
  has_many :poll_votes, dependent: :destroy

  validates :tweet_id, uniqueness: true

  # Builds a poll from the composer's parallel `poll[options][]` and
  # `poll[duration]` fields. Returns nil when the writer did not ask for a poll
  # or supplied fewer than two real choices, so a half-filled poll is dropped
  # rather than saved as a broken one.
  def self.build_for(tweet, options:, duration:)
    labels = Array(options).map { |label| label.to_s.strip }.reject(&:empty?).first(MAX_OPTIONS)
    return nil if labels.size < MIN_OPTIONS

    span = DURATIONS.fetch(duration.to_s, 1.day)

    poll = new(tweet: tweet, closes_at: span.from_now)
    labels.each_with_index do |label, index|
      poll.poll_options.new(label: label.first(MAX_LABEL), position: index)
    end
    poll
  end

  def closed?
    closes_at.present? && closes_at <= Time.current
  end

  # Votes cast, excluding accounts the viewer may not see.
  def total_votes
    poll_votes.count
  end

  def voted_by?(user)
    return false if user.nil?

    poll_votes.exists?(user_id: user.id)
  end

  # The percentage each choice holds, as whole numbers that sum to 100. The
  # remainder goes to the largest share so the split always adds up rather
  # than reading as 99%.
  def shares
    total = total_votes
    return Hash.new(0) if total.zero?

    counts = poll_votes.group(:poll_option_id).count
    raw = poll_options.map { |option| [ option.id, (counts[option.id].to_i * 100.0 / total) ] }
    floors = raw.map { |id, value| [ id, value.floor ] }.to_h

    remainder = 100 - floors.values.sum
    if remainder.positive?
      order = raw.sort_by { |id, value| [ -(value - value.floor), id ] }.map(&:first)
      order.first(remainder).each { |id| floors[id] += 1 }
    end

    floors
  end

  def winning_option_id
    counts = poll_votes.group(:poll_option_id).count
    return nil if counts.empty?

    counts.max_by { |id, count| [ count, -id ] }&.first
  end
end