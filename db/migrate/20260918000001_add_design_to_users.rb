class AddDesignToUsers < ActiveRecord::Migration[8.1]
  # Which era of the client an account sees. Separate from `theme` (light/dark):
  # that picks a palette, this picks the whole shell - navigation and layout.
  # "2019" is the current design and the default every existing row gets.
  def change
    add_column :users, :design, :string, default: "2019", null: false
  end
end
