# A post saved for later by one account.
#
# Private by construction: nothing outside the owner's own bookmark list reads
# this table, and no other account can tell whether a post has been saved.
class Bookmark < ApplicationRecord
  belongs_to :user
  belongs_to :tweet

  validates :user_id, uniqueness: { scope: :tweet_id }

  scope :recent, -> { order(created_at: :desc, id: :desc) }
end