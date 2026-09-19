# One choice on a poll. Position preserves the order the writer entered them,
# which is the order a reader sees.
class PollOption < ApplicationRecord
  belongs_to :poll, inverse_of: :poll_options
  has_many :poll_votes, dependent: :destroy

  validates :label, presence: true, length: { maximum: Poll::MAX_LABEL }
end