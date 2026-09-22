# A canned action-and-reason combination an operator applies in one step.
#
# Consistency in moderation messaging comes from the wording being reused, not
# from retraining: two operators looking at the same violation should write the
# same reason, and a macro is what makes that the easy path. A template stores
# the action, the wording, and the parameters that action takes (a duration, a
# warning category). It never stores a target.
#
# A template grants no authority of its own. Applying one is an action on one
# account, run through the same guards as the hand-written form - the action's
# own permission, the owner check, the rank check - so a macro can add nothing
# a manual action could not. A permanent ban is deliberately not offered as a
# macro: it needs a second operator's approval, and a one-step canned action
# would quietly route around that.
class EnforcementTemplate < ApplicationRecord
  # The actions a macro can stand for, with the permission each still requires
  # when it is applied. `takes_duration` and `takes_category` say which of the
  # extra fields the editor shows for that action.
  ACTIONS = {
    "warn"    => { label: "Issue warning", permission: "users.warn",
                   takes_duration: true, takes_category: true },
    "ban"     => { label: "Timed ban", permission: "users.ban",
                   takes_duration: true, takes_category: false },
    "suspend" => { label: "Suspend account", permission: "users.suspend",
                   takes_duration: false, takes_category: false }
  }.freeze

  MAX_NAME = 80
  MAX_REASON = 1000

  belongs_to :created_by, class_name: "User", optional: true

  scope :active, -> { where(active: true) }
  scope :recent, -> { order(created_at: :desc, id: :desc) }

  validates :name, presence: true, length: { maximum: MAX_NAME }
  validates :action_key, inclusion: { in: ACTIONS.keys }
  validates :reason, presence: true, length: { maximum: MAX_REASON }

  before_validation :apply_defaults
  validate :duration_matches_action
  validate :category_matches_action

  # The duration options an action takes, as [value, label] pairs. Warnings have
  # their own ladder (and a "does not expire" default); a ban uses the same
  # timed ladder the ban form does. Actions that take no duration return none.
  def self.duration_choices(action_key)
    case action_key.to_s
    when "warn" then BanPolicy::WARNING_DURATION_CHOICES
    when "ban"  then BanPolicy::DURATION_CHOICES
    else []
    end
  end

  def self.duration_values(action_key)
    duration_choices(action_key).map(&:first)
  end

  def permission
    ACTIONS.fetch(action_key, {})[:permission]
  end

  def action_label
    ACTIONS.fetch(action_key, {})[:label] || action_key.titleize
  end

  def duration_label
    self.class.duration_choices(action_key).to_h.fetch(duration, duration.presence)
  end

  def category_label
    return nil if category.blank?

    UserWarning::CATEGORIES.fetch(category, category.titleize)
  end

  # One line for the picker on the account record: what the macro would do and
  # the wording it would record, so the operator chooses with the effect in
  # view rather than after the fact.
  def summary
    parts = [ action_label ]
    parts << duration_label if duration.present? && self.class.duration_choices(action_key).any?
    parts.join(" - ")
  end

  private

  def apply_defaults
    self.name = name.to_s.strip
    self.reason = reason.to_s.strip
    self.action_key = action_key.to_s

    if action_key == "warn" && duration.blank?
      self.duration = "none"
    end
    if action_key == "ban" && duration.blank?
      self.duration = "7d"
    end
  end

  def duration_matches_action
    return if action_key.blank?

    values = self.class.duration_values(action_key)

    if values.empty?
      errors.add(:duration, "does not apply to this action") if duration.present?
    elsif !values.include?(duration)
      errors.add(:duration, "is not a valid choice for this action")
    end
  end

  def category_matches_action
    if action_key == "warn"
      errors.add(:category, "is not a valid warning category") unless UserWarning::CATEGORIES.key?(category)
    elsif category.present?
      errors.add(:category, "does not apply to this action")
    end
  end
end
