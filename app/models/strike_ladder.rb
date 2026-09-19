# The escalation ladder an operator is expected to climb when an account keeps
# being warned: each rung names a consequence and the number of standing
# warnings that reaches it.
#
# It is deliberately advisory. A warning is the only action that changes nothing
# about the account, so the ladder must not decide for the operator - an
# account with a clean decade behind it and one on its fifth warning in a week
# can reach the same count, and only a person can tell them apart. The ladder
# is read out on the account record so the next consequence is on screen before
# anyone reaches for the controls, and nothing is applied automatically.
class StrikeLadder
  Rung = Struct.new(:strikes, :label, :consequence, :tone, keyword_init: true)

  # The rungs, ascending. The count is the number of active warnings at which
  # the rung is reached; the consequence describes what staff conventionally do
  # there rather than what the panel does.
  RUNGS = [
    Rung.new(strikes: 1, tone: "warn", label: "Notice",
             consequence: "Warning on record. No restriction; the next reviewer sees it."),
    Rung.new(strikes: 3, tone: "warn", label: "Elevated",
             consequence: "Consider a short suspension and a visibility limit."),
    Rung.new(strikes: 5, tone: "bad", label: "Final warning",
             consequence: "Consider a longer suspension or a timed ban."),
    Rung.new(strikes: 7, tone: "bad", label: "Permanent ban",
             consequence: "Consider a permanent ban. Escalate before acting if the account is tagged for review.")
  ].freeze

  # The rung a count of active warnings has reached, or nil below the first.
  def self.current(count)
    RUNGS.select { |rung| count >= rung.strikes }.last
  end

  # The rung after the one reached, or nil at the top of the ladder.
  def self.next(count)
    RUNGS.find { |rung| count < rung.strikes }
  end

  # Warnings still needed to reach the next rung, or nil at the top.
  def self.remaining(count)
    upcoming = self.next(count)
    upcoming && upcoming.strikes - count
  end

  def self.all
    RUNGS
  end
end
