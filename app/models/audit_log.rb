class AuditLog < ApplicationRecord
  belongs_to :actor, class_name: "User", optional: true

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def self.record(actor:, action:, target: "", detail: "")
    create!(actor: actor, action: action, target: target, detail: detail)
  end
end