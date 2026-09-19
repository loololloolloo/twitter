module BanPolicy
  DURATION_CHOICES = [
    [ "1h", "1 hour" ], [ "1d", "1 day" ], [ "3d", "3 days" ],
    [ "7d", "7 days" ], [ "30d", "30 days" ], [ "365d", "1 year" ]
  ].freeze

  SPANS = {
    "1h" => 1.hour, "1d" => 1.day, "3d" => 3.days,
    "7d" => 7.days, "30d" => 30.days, "365d" => 365.days
  }.freeze

  # Maps a duration choice to an expiry time, or nil for a permanent ban.
  def ban_expiry(choice)
    span = SPANS[choice.to_s]
    span ? Time.current + span : nil
  end

  # Renders a ban end time as "in 2 days" / "in about 3 hours".
  #
  # The count is rounded up so a ban set for "3 days" reads as 3 days rather
  # than 2 days 23:59:59 because of the fraction of a second that elapses
  # before the page renders.
  def humanize_until(expires_at)
    return "" if expires_at.blank?

    seconds = ((expires_at.to_time - Time.current) + 0.999).to_i
    return "moments from now" if seconds <= 0

    days, remainder = seconds.divmod(86_400)
    hours, remainder = remainder.divmod(3_600)
    minutes = remainder / 60

    return "#{days} #{'day'.pluralize(days)}" if days.positive?
    return "#{hours} #{'hour'.pluralize(hours)}" if hours.positive?
    return "#{minutes} #{'minute'.pluralize(minutes)}" if minutes.positive?

    "less than a minute"
  end

  def ban_duration_choices
    DURATION_CHOICES
  end

  # Warnings expire on the same ladder as bans, plus "no expiry": a warning
  # that never lapses is the common case, so it is the default rather than one
  # of the timed options.
  WARNING_DURATION_CHOICES = [
    [ "none", "Does not expire" ], [ "30d", "30 days" ],
    [ "90d", "90 days" ], [ "365d", "1 year" ]
  ].freeze

  WARNING_SPANS = { "30d" => 30.days, "90d" => 90.days, "365d" => 365.days }.freeze

  def warning_expiry(choice)
    span = WARNING_SPANS[choice.to_s]
    span ? Time.current + span : nil
  end

  def warning_duration_choices
    WARNING_DURATION_CHOICES
  end
end