class AddKindToLikes < ActiveRecord::Migration[8.1]
  # Starring a post and liking it are two different reactions, so a single
  # `likes` row per person no longer expresses both. Existing rows are likes,
  # matching how they behaved before the split.
  def up
    add_column :likes, :kind, :string, null: false, default: "like"

    remove_index :likes, name: "index_likes_on_user_id_and_tweet_id"
    add_index :likes, [ :user_id, :tweet_id, :kind ], unique: true,
              name: "index_likes_on_user_id_and_tweet_id_and_kind"

    # Two reactions from the same person on the same post must both be able to
    # coexist, so the old one-per-person constraint is replaced by one per
    # person per reaction.
  end

  def down
    remove_index :likes, name: "index_likes_on_user_id_and_tweet_id_and_kind"
    add_index :likes, [ :user_id, :tweet_id ], unique: true
    remove_column :likes, :kind
  end
end