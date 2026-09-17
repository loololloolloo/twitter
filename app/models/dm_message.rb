class DmMessage < ApplicationRecord
  belongs_to :dm_conversation
  belongs_to :sender, class_name: "User"

  validates :body, presence: true, length: { maximum: 500 }

  scope :chronological, -> { order(created_at: :asc, id: :asc) }
end