class AddMediaUrlToTweets < ActiveRecord::Migration[8.1]
  # A post carries at most one attachment, which is either a file stored on
  # disk (`media_path`) or one embedded from a link (`media_url`). A GIF is
  # usually offered as a link, so it needs somewhere to live that is not the
  # upload directory.
  def change
    add_column :tweets, :media_url, :string
  end
end