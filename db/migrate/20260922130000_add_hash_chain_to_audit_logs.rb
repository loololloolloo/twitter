class AddHashChainToAuditLogs < ActiveRecord::Migration[8.1]
  # The audit trail is the control that makes broad tool access tolerable, so
  # it has to be tamper-evident rather than append-only by convention. Each row
  # now commits to the one before it: `prev_hash` names the predecessor's
  # digest and `chain_hash` is the digest of this row's own fields folded
  # together with that predecessor. Editing or deleting a row in the middle
  # leaves every later digest pointing at a hash that no longer exists, which
  # the verification screen reports.
  #
  # `seq` is the chain position. The digest cannot key off `id`, because
  # SQLite hands a deleted row's id to the next insert, and it cannot key off
  # `created_at`, because two entries written in one transaction can share a
  # timestamp. A monotonic counter makes "the row before this one"
  # unambiguous, which is exactly what a hash chain needs.
  #
  # Rows written before this migration keep an empty digest and a null `seq`;
  # the verifier reports them as unhashed rather than pretending they are
  # covered.
  def change
    add_column :audit_logs, :prev_hash, :string, null: false, default: ""
    add_column :audit_logs, :chain_hash, :string, null: false, default: ""
    add_column :audit_logs, :seq, :integer
    add_index :audit_logs, :seq, unique: true
  end
end
