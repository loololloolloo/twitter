class CreateEnforcementTemplates < ActiveRecord::Migration[8.1]
  # A canned action-and-reason combination. The same violation is described the
  # same way every time because the operator picks the macro rather than
  # retyping the wording, which is what actually moves consistency - training
  # does not.
  #
  # A template stores the action, the wording and, where the action takes one,
  # the duration and warning category. It never stores a target: applying one
  # is still an action on one account, run through the same guards as the
  # hand-written form, so a macro can add nothing a manual action could not.
  def change
    create_table :enforcement_templates do |t|
      t.string :name, null: false
      # One of EnforcementTemplate::ACTIONS.keys. Kept as a string so adding an
      # action does not need a migration.
      t.string :action_key, null: false
      # The canned text that becomes the sanction's reason and, for a warning,
      # the notification the member reads.
      t.text :reason, null: false, default: ""
      # Only meaningful for warn/ban; empty for the actions that take neither.
      t.string :duration, null: false, default: ""
      # Only meaningful for warn; mirrors UserWarning::CATEGORIES.
      t.string :category, null: false, default: ""
      # Disabling keeps the row so the trail can still name the macro an
      # operator applied months ago.
      t.boolean :active, null: false, default: true
      # How many times the macro has been applied, so a stale one is visible
      # rather than being guessed at.
      t.integer :uses_count, null: false, default: 0
      t.integer :created_by_id

      t.timestamps
    end

    # Names are unique case-insensitively: two macros reading "Spam" and "spam"
    # are the same wording under two labels, which is exactly the drift the
    # feature exists to remove. The expression index enforces that in SQLite.
    add_index :enforcement_templates, "LOWER(name)", unique: true,
              name: "index_enforcement_templates_on_lower_name"
    add_index :enforcement_templates, :action_key
  end
end
