class Session < ApplicationRecord
  belongs_to :user

  EXPIRY = 30.days

  scope :active, -> { where("expires_at > ?", Time.current) }

  def self.issue(user)
    create!(user: user, token: SecureRandom.urlsafe_base64(32), expires_at: EXPIRY.from_now)
  end
end