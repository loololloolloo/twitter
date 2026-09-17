# Somebody opened a profile. 2015 Twitter showed no public count for these, so
# this exists to shape bot behaviour and to support internal reporting.
class ProfileView < ApplicationRecord
  belongs_to :user
  belongs_to :viewer, class_name: "User"

  def self.record!(user:, viewer:)
    create!(user: user, viewer: viewer)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    nil
  end
end