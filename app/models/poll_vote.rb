# One account's vote on one poll. The unique index on [poll_id, user_id] is the
# real guard against a second vote; the controller checks first only so the
# reader gets a message rather than a constraint violation.
class PollVote < ApplicationRecord
  belongs_to :poll
  belongs_to :poll_option
  belongs_to :user

  validates :user_id, uniqueness: { scope: :poll_id }
  validate :option_belongs_to_poll

  private

  # A vote names an option and a poll separately, so nothing in the schema stops
  # them disagreeing. Counting such a vote would credit one poll with a choice
  # from another.
  def option_belongs_to_poll
    return if poll_id.blank? || poll_option_id.blank?
    return if poll_option&.poll_id == poll_id

    errors.add(:poll_option_id, "does not belong to that poll")
  end
end