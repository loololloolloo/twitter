# One account stopping another from interacting with it.
#
# The block is mutual in effect: neither account appears in the other's
# timeline, profile, search results or suggestions. Unlike a mute, the blocked
# account cannot follow the blocker, and blocking an existing follower removes
# that follow.
#
# The two directions read from two different columns, which is why both are
# indexed: "have I blocked them" reads `blocker_id`, "are they blocking me"
# reads `blocked_id`, and the timeline under a signed-in account has to ask both.
class Block < ApplicationRecord
  belongs_to :blocker, class_name: "User"
  belongs_to :blocked, class_name: "User"

  validates :blocker_id, uniqueness: { scope: :blocked_id }
  validate :not_self

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  private

  def not_self
    errors.add(:blocked_id, "cannot block yourself") if blocker_id == blocked_id
  end
end