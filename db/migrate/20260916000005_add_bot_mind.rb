class AddBotMind < ActiveRecord::Migration[8.1]
  def change
    # Evolving per-account state: mood, current fixations, opinions it has
    # formed and who it has been talking to. Keeping it beside `persona` lets a
    # bot's output drift over time instead of restarting from the same
    # templates on every action, without needing a column per trait.
    add_column :users, :mind, :text, null: false, default: "{}"
  end
end