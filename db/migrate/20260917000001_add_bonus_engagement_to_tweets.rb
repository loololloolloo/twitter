class AddBonusEngagementToTweets < ActiveRecord::Migration[8.1]
  # A post's displayed engagement can outrun the number of accounts that could
  # possibly have reacted. There are only ~5,000 simulated accounts, so a post
  # showing six figures of likes has no row per like and cannot have one.
  #
  # These columns carry the part of each count that has no rows behind it, the
  # same way `users.bonus_followers` tops up a follower total that has outgrown
  # the population. Real likes and retweets from accounts stay in their own
  # tables and are added on top, so liking a post still works and still moves
  # the number by one.
  def change
    add_column :tweets, :bonus_likes, :integer, null: false, default: 0
    add_column :tweets, :bonus_retweets, :integer, null: false, default: 0
    add_column :tweets, :bonus_favourites, :integer, null: false, default: 0
  end
end