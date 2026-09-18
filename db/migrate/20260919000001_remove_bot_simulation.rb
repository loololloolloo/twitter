class RemoveBotSimulation < ActiveRecord::Migration[8.1]
  # The simulated population is gone: accounts, engine, scheduler and the
  # admin screens that drove them. What is left behind is the schema that
  # supported them, which is dropped here.
  #
  # `bonus_followers` is deliberately kept - it is an administrator grant that
  # predates the simulation and is still used on the admin user page.
  def up
    remove_column :users, :is_bot
    remove_column :users, :persona
    remove_column :users, :mind
    remove_column :users, :next_action_at
    remove_column :users, :last_action_at
    remove_column :users, :actions_performed
    remove_column :users, :repeat_followers
  end

  def down
    add_column :users, :is_bot, :boolean, null: false, default: false
    add_column :users, :persona, :text, null: false, default: "{}"
    add_column :users, :mind, :text, null: false, default: "{}"
    add_column :users, :next_action_at, :datetime
    add_column :users, :last_action_at, :datetime
    add_column :users, :actions_performed, :integer, null: false, default: 0
    add_column :users, :repeat_followers, :integer, null: false, default: 0

    add_index :users, :next_action_at
    add_index :users, [ :is_bot, :next_action_at ]
    add_index :users, :repeat_followers
  end
end
