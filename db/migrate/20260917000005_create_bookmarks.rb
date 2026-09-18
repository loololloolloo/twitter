class CreateBookmarks < ActiveRecord::Migration[8.1]
  # Bookmarks are private to the account that made them. Unlike a like, nobody
  # else can see them and they never appear on a profile, which is why they are
  # their own table rather than another `likes.kind`.
  def change
    create_table :bookmarks do |t|
      t.references :user, null: false, foreign_key: true
      t.references :tweet, null: false, foreign_key: true

      t.timestamps
    end

    add_index :bookmarks, [ :user_id, :tweet_id ], unique: true
    add_index :bookmarks, [ :user_id, :created_at ]
  end
end