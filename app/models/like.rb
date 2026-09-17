class Like < ApplicationRecord
  # Starring ("favourite") and the newer heart ("like") are independent
  # reactions: a person can do either or both to the same post, and each has
  # its own count and colour in the client.
  FAVOURITE = "favourite".freeze
  LIKE = "like".freeze
  KINDS = [ FAVOURITE, LIKE ].freeze

  belongs_to :user
  belongs_to :tweet

  validates :kind, inclusion: { in: KINDS }
  validates :user_id, uniqueness: { scope: [ :tweet_id, :kind ] }

  scope :favourites, -> { where(kind: FAVOURITE) }
  scope :likes, -> { where(kind: LIKE) }
end