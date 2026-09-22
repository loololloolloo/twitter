# One per-account evidence export. A record of the disclosure itself: an export
# is not a read, it is handing the account's material to someone outside the
# panel, so the reason it was asked for has to outlive the request.
#
# The snapshot is written here rather than only recorded in the audit trail for
# two reasons: the audit chain is tamper-evident history and may be pruned by
# an operator, while a legal hold or data request has to be answerable years
# later; and the reason is the point of the row - "exported 12 posts" on its own
# does not say whether the disclosure was justified.
class DataExport < ApplicationRecord
  belongs_to :user
  belongs_to :actor, class_name: "User", optional: true

  MAX_REASON = 280

  validates :reason, presence: true, length: { maximum: MAX_REASON }

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def summary
    "exported #{post_count} post(s) and #{enforcement_count} enforcement entr(ies)"
  end
end
