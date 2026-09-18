class AddRepeatFollowersToUsers < ActiveRecord::Migration[8.1]
  # Followers an account has beyond the accounts that exist.
  #
  # A bot follows an account once - the unique index on `follows` says so - so
  # while the population is smaller than the number of followers a popular
  # account should have, the count would stall at the size of the population.
  # Every further follow a bot aims at an account it already follows adds to
  # this counter instead, which is what lets a famous account keep climbing.
  #
  # A counter rather than rows: a million followers would be a million rows
  # that no query walks, and `follows.follower_id` carries a foreign key to
  # `users`, so a row without an account behind it cannot exist anyway.
  def change
    add_column :users, :repeat_followers, :integer, null: false, default: 0
    add_index :users, :repeat_followers
  end
end
