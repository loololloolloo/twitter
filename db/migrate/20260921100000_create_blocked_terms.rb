class CreateBlockedTerms < ActiveRecord::Migration[8.1]
  # An operator-managed list of terms that the site acts on. The mode is the
  # point of the row: "hide" removes a matching post from every timeline, while
  # "flag" leaves it in place and only marks it in the panel. Those are very
  # different blast radii, so the mode is stored per term and shown in plain
  # words on the screen rather than being a global switch.
  def change
    create_table :blocked_terms do |t|
      t.string :term, null: false
      # "hide" or "flag"; see BlockedTerm::MODES.
      t.string :mode, null: false, default: "flag"
      t.string :category, null: false, default: "other"
      t.text :note, null: false, default: ""
      t.boolean :active, null: false, default: true
      t.integer :created_by_id

      t.timestamps
    end

    # Case-insensitive, to match the model's rule: "Spam" and "spam" are the
    # same rule to everyone except a byte-comparing index.
    add_index :blocked_terms, "LOWER(term)", unique: true, name: "index_blocked_terms_on_lower_term"
    add_index :blocked_terms, :active
  end
end
