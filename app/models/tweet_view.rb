# An impression: somebody opened a tweet. The row is what makes a session read
# as browsing, and it also stops a bot from reopening a post it has just read.
class TweetView < ApplicationRecord
  belongs_to :tweet
  belongs_to :user

  validates :tweet_id, uniqueness: { scope: :user_id }

  # Records that `user` looked at `tweet`. Repeat views are ignored rather than
  # erroring, because a bot may well open the same post again later.
  def self.record!(user:, tweet:, dwell_seconds: 0)
    create!(user: user, tweet: tweet, dwell_seconds: dwell_seconds)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    nil
  end
end