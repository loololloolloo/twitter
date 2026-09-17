class RepairDottedBotUsernames < ActiveRecord::Migration[8.1]
  # BotFactory generated some handles containing a period, because its
  # sanitizer allowed one and `insert_all` skips the model's USERNAME_FORMAT
  # validation. A name like "aaron.chen" does not merely look wrong: the route
  # /u/aaron.chen parses as username "aaron" plus format "chen", so the profile
  # is unreachable, and any `update!` on the record fails validation, which
  # breaks suspending, verifying, banning and assigning a picture.
  #
  # The dot is removed rather than replaced, matching the fixed generator, and
  # a suffix disambiguates any collision that creates.
  def up
    ids = select_values(<<~SQL)
      SELECT id FROM users
      WHERE is_bot = 1 AND username LIKE '%.%'
      ORDER BY id
    SQL
    return if ids.empty?

    taken = select_values("SELECT username FROM users").to_set

    ids.each do |id|
      username = select_value("SELECT username FROM users WHERE id = #{id.to_i}")
      candidate = username.delete(".")[0, 15]

      if taken.include?(candidate)
        suffix = 1
        suffix += 1 while taken.include?("#{candidate[0, 15 - suffix.to_s.length]}#{suffix}")
        candidate = "#{candidate[0, 15 - suffix.to_s.length]}#{suffix}"
      end

      taken << candidate
      execute("UPDATE users SET username = #{quote(candidate)}, " \
              "email = #{quote("#{candidate}@example.com")} WHERE id = #{id.to_i}")
    end
  end

  def down
    # The original dotted handles were not recorded, and reintroducing an
    # unrouteable username would restore the bug, so this is not reversible.
    raise ActiveRecord::IrreversibleMigration
  end
end