class ModeratorSetting < ApplicationRecord
  belongs_to :user

  MIN_BREAK_MINUTES = 15
  MAX_BREAK_MINUTES = 480
  DEFAULT_BREAK_MINUTES = 90
  # How long a snooze pushes the reminder back. Long enough to finish the item
  # in hand, short enough that it cannot quietly become "off".
  SNOOZE_MINUTES = 15

  # One row per operator, created the first time their wellness state is read.
  def self.for(user)
    find_or_create_by!(user_id: user.id)
  end

  # True once `break_reminder_minutes` of work have elapsed since the current
  # interval began. Both taking a break and snoozing move the interval forward,
  # so this is a measure from the last acknowledgement and does not need a
  # separate dismissal flag that could drift out of step with it.
  def break_due?(now = Time.current)
    started = shift_started_at || last_break_at
    return false if started.nil?

    now - started >= break_reminder_minutes.minutes
  end

  def start_shift!(now = Time.current)
    update!(shift_started_at: now, last_break_at: now)
  end

  # Taking a break restarts the interval, whether the operator was prompted or
  # simply stepped away on their own.
  def take_break!(now = Time.current)
    update!(last_break_at: now, shift_started_at: now)
  end

  # Snoozing resets the interval too, so the prompt returns one configured
  # interval later rather than immediately.
  def snooze!(now = Time.current)
    update!(last_break_at: now, shift_started_at: now)
  end

  # Minutes since the current interval began; 0 until the shift does.
  def minutes_since_break(now = Time.current)
    started = shift_started_at || last_break_at
    return 0 if started.nil?

    ((now - started) / 60).floor
  end
end
