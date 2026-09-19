# A private, attributed note an operator leaves on an account. It is the
# running commentary the audit trail cannot carry: the trail records what was
# done, not what staff noticed while doing it, and the tag note is a single
# field that overwrites. A note is never shown to the member, never notified,
# and never changes the account - it only tells the next operator what someone
# already knew.
class StaffNote < ApplicationRecord
  belongs_to :user
  belongs_to :author, class_name: "User", optional: true

  MAX_BODY = 2_000

  validates :body, presence: true, length: { maximum: MAX_BODY }

  # Pinned notes lead the list whatever their age; the rest read newest first.
  # An operator pins the standing context (who this account is, what was agreed
  # with them) and leaves the incidental observations to sort by time.
  scope :ordered, -> { order(pinned: :desc, created_at: :desc, id: :desc) }

  def author_label
    author ? "@#{author.username}" : "system"
  end
end
