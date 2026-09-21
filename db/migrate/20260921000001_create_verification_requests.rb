class CreateVerificationRequests < ActiveRecord::Migration[8.1]
  # A member's request for the verified badge, and the operator's decision on
  # it. Approving is what grants the badge, so the decision is the grant: there
  # is no separate toggle to forget, and a granted badge always has a request
  # behind it naming who approved it and why.
  #
  # The request carries a snapshot of what the member said about themselves,
  # because the account record can change between filing and review and the
  # decision should be read against the case that was actually made.
  #
  # There is no foreign key on `reviewed_by_id`, following staff_notes and
  # appeals: an operator may be deleted and the request should still read as
  # history.
  def change
    create_table :verification_requests do |t|
      t.integer :user_id, null: false
      # What the account is asking to be verified as.
      t.string :category, null: false, default: "other"
      # Why the account should carry the badge.
      t.text :body, null: false, default: ""

      t.string :state, null: false, default: "pending"
      t.integer :reviewed_by_id
      t.text :decision_note, null: false, default: ""
      t.datetime :decided_at

      t.timestamps
    end

    add_index :verification_requests, :user_id
    add_index :verification_requests, :state
    add_index :verification_requests, [ :state, :created_at ]
  end
end
