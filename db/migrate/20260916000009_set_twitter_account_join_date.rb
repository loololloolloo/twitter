class SetTwitterAccountJoinDate < ActiveRecord::Migration[8.1]
  # @twitter is the site's own account and the profile should read like one:
  # a long-standing account, not one created when the row happened to be
  # inserted. A fixed 2015 date keeps the profile stable across reseeds instead
  # of drifting with the clock.
  JOINED_AT = "2015-03-21 09:00:00".freeze

  def up
    execute(
      "UPDATE users SET created_at = '#{JOINED_AT}' WHERE username = 'twitter'"
    )
  end

  def down
    # The original value is not recorded, so the rollback only has to stop the
    # date from being pinned; a reseed re-establishes it.
    execute(
      "UPDATE users SET created_at = '#{Time.current.utc.strftime('%Y-%m-%d %H:%M:%S')}' WHERE username = 'twitter'"
    )
  end
end
