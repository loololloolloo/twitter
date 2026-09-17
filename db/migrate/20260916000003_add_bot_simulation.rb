class AddBotSimulation < ActiveRecord::Migration[8.1]
  def change
    # Bots are ordinary users so they can own tweets, follows, likes and
    # conversations; the flag is what tells them apart from real members.
    add_column :users, :is_bot, :boolean, null: false, default: false

    # Persona and scheduling state. `persona` holds the generated voice
    # profile (archetype, interests, cadence) as JSON so the generator can
    # evolve without a migration.
    add_column :users, :persona, :text, null: false, default: "{}"
    add_column :users, :next_action_at, :datetime
    add_column :users, :last_action_at, :datetime
    add_column :users, :actions_performed, :integer, null: false, default: 0

    # The engine polls for bots that are due to act; the partial index keeps
    # that scan cheap no matter how large the users table grows.
    add_index :users, :next_action_at
    add_index :users, [ :is_bot, :next_action_at ]

    # Follows and likes are written in bulk by the engine and read constantly
    # when rendering timelines, so index the columns the engine filters on.
    add_index :tweets, :created_at
    add_index :dm_messages, [ :dm_conversation_id, :created_at ]
  end
end