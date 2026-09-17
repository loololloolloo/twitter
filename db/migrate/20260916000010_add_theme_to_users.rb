class AddThemeToUsers < ActiveRecord::Migration[8.1]
  # The theme is stored per account rather than in the browser so it follows a
  # member between devices. "light" is the default, which is what every existing
  # row gets.
  def change
    add_column :users, :theme, :string, default: "light", null: false
  end
end
