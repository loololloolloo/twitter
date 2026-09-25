class AddReviewReasonToUsers < ActiveRecord::Migration[8.1]
  # The elevated-handling flag (`requires_review`) is the panel's answer to
  # Meta's Cross-Check: an account that is handled differently from the rest.
  # Raising it changes who owns a decision about the account, so it records why.
  # That reason lives in its own column rather than in `tag_note`, because the
  # note is the account's standing working description and is rewritten on the
  # next tag edit, while the reason belongs to this flag being raised and has to
  # survive that edit.
  def change
    add_column :users, :review_reason, :text, null: false, default: ""
  end
end
