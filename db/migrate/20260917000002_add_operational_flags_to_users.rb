class AddOperationalFlagsToUsers < ActiveRecord::Migration[8.1]
  # The internal tool the redesign is modelled on marks accounts with a set of
  # operational flags that a moderator toggles directly on the user page. They
  # are deliberately separate from the ban/suspend columns: none of them removes
  # an account, they only describe how it should be treated.
  #
  # `reports` and `pinned_at` support two features the permission registry
  # already advertised but nothing implemented: the moderation queue behind
  # reports.view / reports.resolve, and pinning behind tweets.pin.
  def change
    add_column :users, :search_blacklist, :boolean, null: false, default: false
    add_column :users, :trends_blacklist, :boolean, null: false, default: false
    add_column :users, :do_not_amplify, :boolean, null: false, default: false
    add_column :users, :is_compromised, :boolean, null: false, default: false
    add_column :users, :is_high_profile, :boolean, null: false, default: false
    add_column :users, :requires_review, :boolean, null: false, default: false
    add_column :users, :tag_note, :text, null: false, default: ""

    add_column :tweets, :pinned_at, :datetime
  end
end
