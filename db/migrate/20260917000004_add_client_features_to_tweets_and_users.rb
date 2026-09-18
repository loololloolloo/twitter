class AddClientFeaturesToTweetsAndUsers < ActiveRecord::Migration[8.1]
  # Columns the 2019 web client needs that the schema does not yet carry.
  #
  #   quote_of_id     a quote tweet names the post it quotes. It is a distinct
  #                   thing from a retweet: the quoting account's own words are
  #                   the body, and the quoted post is attached beneath.
  #   alt_text        the description attached to an uploaded image, which the
  #                   client shows as the image's alternative text.
  #   reply_hidden_at when the author hid a reply, so it drops out of the
  #                   thread for everyone but its own author.
  #   protected       a protected account's posts are only readable by its
  #                   approved followers.
  def change
    add_column :tweets, :quote_of_id, :integer
    add_column :tweets, :alt_text, :string
    add_column :tweets, :reply_hidden_at, :datetime

    add_column :users, :protected, :boolean, null: false, default: false

    add_index :tweets, :quote_of_id
    add_index :tweets, :reply_hidden_at
  end
end