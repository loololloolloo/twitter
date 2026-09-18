# A curated timeline of accounts, read without following them.
#
# The point of a list is to read a set of accounts without their posts landing
# in the home timeline and without following them, so membership is independent
# of the follow graph. A private list is only visible to its owner.
class List < ApplicationRecord
  belongs_to :user
  has_many :list_memberships, dependent: :destroy
  has_many :members, through: :list_memberships, source: :user

  validates :name, presence: true, length: { maximum: 25 }
  validates :description, length: { maximum: 100 }
  validates :name, uniqueness: { scope: :user_id, case_sensitive: false }

  scope :for_owner, ->(owner) { where(user_id: owner) }
  scope :recent, -> { order(created_at: :desc, id: :desc) }

  # The posts from this list's members, in the shape the timeline expects. A
  # list timeline shows original posts and retweets from its members, which is
  # the same rule the home timeline applies to the accounts you follow.
  def timeline(limit: 100)
    ids = list_memberships.select(:user_id)

    Tweet.visible
         .where(user_id: ids)
         .includes(:user, retweet_of: :user, quote_of: :user)
         .recent
         .limit(limit)
  end

  def member_count
    list_memberships.count
  end

  def includes?(account)
    return false if account.nil?

    list_memberships.exists?(user_id: account.id)
  end
end