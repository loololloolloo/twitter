class Role < ApplicationRecord
  has_many :role_permissions, dependent: :destroy
  has_many :permissions, through: :role_permissions
  has_many :users, dependent: :restrict_with_error

  OWNER = "owner".freeze

  def permission_keys
    permissions.pluck(:key).to_set
  end
end