# One account quietly stopping another from appearing in its own view.
#
# One-way and private: the muted account is never told, keeps its follow, and
# still sees the muter's posts. Only the muter's timelines, notifications and
# suggestions drop the muted account.
class Mute < ApplicationRecord
  belongs_to :muter, class_name: "User"
  belongs_to :muted, class_name: "User"

  validates :muter_id, uniqueness: { scope: :muted_id }
  validate :not_self

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  private

  def not_self
    errors.add(:muted_id, "cannot mute yourself") if muter_id == muted_id
  end
end