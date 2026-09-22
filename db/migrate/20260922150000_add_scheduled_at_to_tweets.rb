class AddScheduledAtToTweets < ActiveRecord::Migration[8.1]
  # The 2019 composer's last toolbar control scheduled a post for later. The
  # schedule lived on the draft rather than on a separate table, so the column
  # belongs on the post: a scheduled post is not a second kind of row, it is a
  # post whose `created_at` should be read as the moment it was written, which
  # is why the timeline time is derived rather than reusing `created_at`.
  #
  # Null is the ordinary case - a post made now - so the column is nullable and
  # only the owner's own screens ever show a scheduled row.
  def change
    add_column :tweets, :scheduled_at, :datetime
    add_index :tweets, :scheduled_at
  end
end
