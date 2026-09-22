class AuditLog < ApplicationRecord
  belongs_to :actor, class_name: "User", optional: true

  # The digest the first chained row commits to. Using a fixed well-known value
  # rather than a blank means "the row before this one is missing entirely" is
  # distinguishable from "the previous digest was empty".
  GENESIS = ("0" * 64).freeze

  scope :recent, -> { order(created_at: :desc, id: :desc) }
  scope :chained, -> { where.not(seq: nil) }

  # The exact bytes a row commits to. Every field that carries meaning is
  # included, so altering the actor, the action, the target or the detail
  # changes the digest. Fields are joined with a NUL so that moving text across
  # a boundary cannot produce the same payload.
  def chain_payload
    [
      seq,
      prev_hash.to_s,
      actor_id.to_i,
      action.to_s,
      target.to_s,
      detail.to_s,
      created_at&.utc&.iso8601(6).to_s
    ].join("\u0000")
  end

  def compute_chain_hash
    Digest::SHA256.hexdigest(chain_payload)
  end

  def chained?
    seq.present?
  end

  def self.record(actor:, action:, target: "", detail: "")
    append(actor: actor, action: action, target: target, detail: detail)
  end

  # Appends one entry and seals it into the chain. The whole read-then-write
  # runs inside a transaction so two operators logging at the same moment
  # cannot both read the same tail and fork the chain.
  def self.append(attrs)
    transaction do
      previous = chained.order(seq: :desc).first
      entry = new(**attrs)
      entry.seq = (previous&.seq || 0) + 1
      entry.prev_hash = previous&.chain_hash || GENESIS
      # created_at is part of the digest, so it has to be settled before the
      # hash is computed rather than left for the insert to fill in.
      entry.created_at ||= Time.current
      entry.updated_at = entry.created_at
      entry.chain_hash = entry.compute_chain_hash
      entry.save!
      entry
    end
  end

  # Walks the chain in order and checks two things per row: that its own
  # contents still hash to what it recorded, and that it names the digest of
  # the row before it. Nothing here writes, so it is safe to run at any time.
  # `order(:seq)` rather than `find_each`, which would ignore the ordering the
  # chain depends on.
  def self.verify_chain
    broken = []
    length = 0
    expected_prev = GENESIS

    chained.order(:seq).each do |entry|
      length += 1
      problems = []
      if entry.prev_hash != expected_prev
        problems << "does not follow the previous entry; an entry in between is missing or reordered"
      end
      if entry.compute_chain_hash != entry.chain_hash
        problems << "its contents no longer match the digest it recorded"
      end
      broken << { entry: entry, problems: problems } if problems.any?
      expected_prev = entry.chain_hash
    end

    { length: length, intact: broken.empty?, broken: broken, unhashed: where(seq: nil).count }
  end
end