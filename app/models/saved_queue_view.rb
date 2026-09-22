# A named queue filter an operator saved for themselves. The point is the
# repeated slice: the same state, category and age combination worked shift
# after shift, retyped every time. A view stores the filter values and nothing
# else - the rows are resolved on read - so a view describes a query rather than
# a frozen list, and it can never disagree with the queue it points at.
#
# A view belongs to the operator who saved it. It is a personal shortcut, not a
# shared setting: sharing one operator's default with everyone is exactly the
# wasted time this exists to remove, so the owner is part of the row rather than
# a role-level grant.
class SavedQueueView < ApplicationRecord
  # The queues a view can point at. Only the report queue is wired for now; the
  # column is here so the same mechanism extends without a second table.
  QUEUES = {
    "reports" => "Reports"
  }.freeze

  # The filters a view may carry. The keys are the queue's own query parameter
  # names on purpose, so applying a view is "copy these params" and cannot drift
  # from what the filter form submits.
  FILTERS = %w[state category sort].freeze

  MAX_NAME = 60

  belongs_to :owner, class_name: "User"

  validates :name, presence: true, length: { maximum: MAX_NAME }
  validates :queue, inclusion: { in: QUEUES.keys }
  validate :name_is_unique_for_owner

  scope :for_queue, ->(queue) { where(queue: queue) }
  scope :owned_by, ->(user) { where(owner_id: user.id) }
  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def self.filter_params(view)
    FILTERS.index_with { |key| view.public_send(key).to_s }.reject { |_, value| value.blank? }
  end

  def self.default_for(user, queue)
    owned_by(user).for_queue(queue).find_by(is_default: true)
  end

  # A view is set as default one at a time, because two defaults would leave the
  # queue picking arbitrarily. The clear and the set are in one transaction so a
  # failed write cannot leave the operator with none.
  def make_default!
    self.class.transaction do
      self.class.owned_by(owner).for_queue(queue).where.not(id: id).update_all(is_default: false)
      update!(is_default: true)
    end
  end

  # The view's filters as a sentence, so the screen can state what the named
  # shortcut does without the operator opening it.
  def summary
    parts = []
    parts << "state: #{state}" if state.present?
    parts << "category: #{category}" if category.present?
    parts << (sort == "oldest" ? "oldest first" : "highest risk first") if sort.present?
    parts.presence&.join(", ") || "no filters - the whole queue"
  end

  private

  def name_is_unique_for_owner
    return if name.blank? || owner_id.blank?

    clash = self.class.owned_by(owner).for_queue(queue).where("LOWER(name) = ?", name.strip.downcase)
    clash = clash.where.not(id: id) if persisted?
    errors.add(:name, "is already used by one of your views") if clash.exists?
  end
end
