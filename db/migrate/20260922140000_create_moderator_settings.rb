class CreateModeratorSettings < ActiveRecord::Migration[8.1]
  # Per-operator wellness state. Moderation research is consistent that two
  # tools reduce harm exposure without hurting accuracy: blurring media behind a
  # deliberate reveal, and prompting a break. Both are properties of the person
  # working the queue, not of the account or the post, so they live here rather
  # than on `users.requires_review` or the report row.
  #
  # Blurring defaults on, because the safe state should be the state an operator
  # is already in; it is a concealment the operator lifts on purpose, never a
  # permanent block, which is why the reveal is a one-tap control and not a
  # permission.
  def change
    create_table :moderator_settings do |t|
      t.integer :user_id, null: false
      t.boolean :sensitive_media_blurred, null: false, default: true
      # Minutes of continuous work before the break prompt appears. A shift is
      # not a unit an operator can be trusted to track while reading harm, so
      # the clock runs from when the interval began, not from the first load.
      t.integer :break_reminder_minutes, null: false, default: 90
      # Start of the current work interval. Taking a break and snoozing both
      # move it forward, so the reminder always measures from the last point the
      # operator acknowledged.
      t.datetime :shift_started_at
      t.datetime :last_break_at

      t.timestamps
    end

    add_index :moderator_settings, :user_id, unique: true
  end
end
