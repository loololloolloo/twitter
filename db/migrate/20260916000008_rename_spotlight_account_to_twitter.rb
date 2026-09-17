class RenameSpotlightAccountToTwitter < ActiveRecord::Migration[8.1]
  # The watched account shipped as @cr7 but the display name is "Twitter", so
  # the handle and the profile disagreed. Renaming it also means the default in
  # BotEngine matches an account that actually exists under that name.
  #
  # The rename is skipped rather than forced when @twitter is already taken, so
  # the migration cannot fail or silently merge two accounts on a database that
  # has been edited by hand.
  def up
    names = select_values("SELECT username FROM users").to_set
    return if names.include?("twitter")
    return unless names.include?("cr7")

    execute("UPDATE users SET username = 'twitter', email = 'twitter@example.com' WHERE username = 'cr7'")
  end

  def down
    names = select_values("SELECT username FROM users").to_set
    return if names.include?("cr7")
    return unless names.include?("twitter")

    execute("UPDATE users SET username = 'cr7', email = 'cr7@example.com' WHERE username = 'twitter'")
  end
end
