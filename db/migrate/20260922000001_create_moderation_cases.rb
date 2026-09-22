class CreateModerationCases < ActiveRecord::Migration[8.1]
  # A case turns a pile of reports into one investigation. Reports arrive
  # independently and each is closed on its own; a case is the thing that says
  # these reports are about the same account or the same post and should be
  # decided together. The decision belongs to the case, not to each report, so
  # a cluster does not produce a dozen contradictory one-off outcomes.
  #
  # The operator columns carry no foreign keys, following appeals and
  # staff_notes: an operator may be deleted and the case should still read as
  # history.
  def change
    create_table :moderation_cases do |t|
      # Nullable: a case can be opened about a post alone, before the account
      # behind it is established.
      t.integer :user_id
      t.integer :tweet_id

      t.string :title, null: false, default: ""
      t.text :summary, null: false, default: ""

      t.string :state, null: false, default: "open"
      t.integer :opened_by_id
      t.integer :decided_by_id
      t.text :decision_note, null: false, default: ""
      t.datetime :decided_at

      t.timestamps
    end

    add_index :moderation_cases, :user_id
    add_index :moderation_cases, :tweet_id
    add_index :moderation_cases, :state
    add_index :moderation_cases, [ :state, :created_at ]

    # Which reports belong to which case. A report is on at most one case, so
    # the unique index is the rule: linking a report that is already on a case
    # is a move, not a second link.
    create_table :case_links do |t|
      t.references :moderation_case, null: false, foreign_key: true
      t.references :report, null: false, foreign_key: true, index: { unique: true }
      t.integer :linked_by_id

      t.timestamps
    end
  end
end
