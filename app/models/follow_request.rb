# A pending ask to follow a protected account.
#
# Following a protected account does not create a follow. It creates this, and
# the account has to approve it. Keeping the request as its own row rather than
# a flag on a follow matters because a follow row that does not grant access
# would be indistinguishable from one that does, and every read of the follow
# graph would have to check the flag.
class FollowRequest < ApplicationRecord
  belongs_to :requester, class_name: "User"
  belongs_to :target, class_name: "User"

  STATES = %w[pending approved rejected].freeze

  validates :state, inclusion: { in: STATES }
  validates :requester_id, uniqueness: { scope: :target_id }
  validate :not_self

  scope :pending, -> { where(state: "pending") }
  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def pending?
    state == "pending"
  end

  # Approving turns the request into the follow it was asking for. The follow
  # is created here rather than by the caller so the two cannot drift apart.
  def approve!
    transaction do
      update!(state: "approved")
      Follow.find_or_create_by!(follower_id: requester_id, followee_id: target_id)
    end
  end

  def reject!
    update!(state: "rejected")
  end

  private

  def not_self
    errors.add(:target_id, "cannot request to follow yourself") if requester_id == target_id
  end
end