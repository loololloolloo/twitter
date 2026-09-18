class Notification < ApplicationRecord
  belongs_to :user
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :tweet, optional: true

  KINDS = %w[like favourite retweet quote reply follow follow_request mention admin].freeze

  scope :unread, -> { where(is_read: false) }
  scope :recent, -> { order(created_at: :desc, id: :desc) }
end