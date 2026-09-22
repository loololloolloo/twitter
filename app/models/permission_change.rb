# One edit to a role's permission set. The editor writes a row here whenever a
# save actually changes the set, so the review surface can show the capability
# diff without decoding audit strings. A save that changes nothing writes no row.
class PermissionChange < ApplicationRecord
  belongs_to :role
  belongs_to :actor, class_name: "User", optional: true

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  # Record an edit from the sets on either side of it. Returns nil when the set
  # is unchanged, so a no-op save does not fill the review screen with noise.
  def self.record(role:, actor:, before:, after:, note: "")
    before = normalize(before)
    after = normalize(after)
    return nil if before == after

    create!(
      role: role,
      actor: actor,
      before_keys: before.to_json,
      after_keys: after.to_json,
      note: note.to_s.strip
    )
  end

  def self.normalize(keys)
    Array(keys).map(&:to_s).uniq.sort
  end

  def before
    self.class.normalize(JSON.parse(before_keys))
  end

  def after
    self.class.normalize(JSON.parse(after_keys))
  end

  # The capabilities this edit granted, and the ones it took away. These are
  # the two sides the review screen renders, because "added users.ban" is the
  # sentence that matters, not the full after-list.
  def added
    after - before
  end

  def removed
    before - after
  end

  def changed?
    added.any? || removed.any?
  end

  # A one-line summary for a table cell. Kept in the model so the review screen
  # and any future digest describe the same edit the same way.
  def summary
    parts = []
    parts << "+#{added.size}" if added.any?
    parts << "-#{removed.size}" if removed.any?
    parts.join(" / ")
  end
end
