class Follow < ApplicationRecord
  belongs_to :follower, class_name: "User"
  belongs_to :followee, class_name: "User"

  validates :follower_id, uniqueness: { scope: :followee_id }
  validate :not_self

  private

  def not_self
    errors.add(:followee_id, "cannot follow yourself") if follower_id == followee_id
  end
end