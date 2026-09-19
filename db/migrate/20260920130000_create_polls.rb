class CreatePolls < ActiveRecord::Migration[8.1]
  # A poll belongs to one post and offers two to four choices. The choices are
  # their own rows rather than a serialised column because a vote has to point
  # at exactly one of them, and a foreign key is what makes that countable.
  def change
    create_table :polls do |t|
      t.integer  :tweet_id, null: false
      t.datetime :closes_at
      t.timestamps
    end
    add_index :polls, :tweet_id, unique: true

    create_table :poll_options do |t|
      t.integer :poll_id, null: false
      t.string  :label, null: false, default: ""
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :poll_options, [ :poll_id, :position ]

    create_table :poll_votes do |t|
      t.integer :poll_id, null: false
      t.integer :poll_option_id, null: false
      t.integer :user_id, null: false
      t.timestamps
    end
    # One account votes once. The database enforces it because the controller's
    # check alone would let two simultaneous requests both see "not voted yet".
    add_index :poll_votes, [ :poll_id, :user_id ], unique: true
    add_index :poll_votes, :poll_option_id
  end
end