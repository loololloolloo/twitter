class DmConversation < ApplicationRecord
  belongs_to :user_a, class_name: "User"
  belongs_to :user_b, class_name: "User"
  has_many :dm_messages, dependent: :destroy

  # Conversations are stored with the lower user id first so a pair of users
  # always maps to exactly one row.
  def self.between(left, right)
    a, b = [ left.id, right.id ].sort
    find_or_create_by!(user_a_id: a, user_b_id: b)
  end

  def participants
    [ user_a, user_b ]
  end

  def other_for(user)
    user.id == user_a_id ? user_b : user_a
  end

  def last_message
    dm_messages.chronological.last
  end
end