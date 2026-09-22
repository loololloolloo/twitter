require "test_helper"

# Covers the tamper-evidence on the audit trail. The audit log is the control
# that makes broad tool access tolerable, so it cannot rely on nobody having
# write access: every entry commits to the one before it, and the verification
# screen re-walks that chain. These tests check that an untouched log verifies,
# that an edited row and a deleted row are both caught, and that the screen is
# gated on the same grant as reading the log.
class AdminAuditIntegrityTest < ActionDispatch::IntegrationTest
  def entries(count)
    count.times { |i| AuditLog.record(actor: nil, action: "test.action.#{i}", target: "user:1", detail: "step #{i}") }
  end

  test "each entry is sealed to the one before it" do
    entries(3)

    chain = AuditLog.chained.order(:seq).to_a
    assert_equal [ 1, 2, 3 ], chain.map(&:seq)
    assert_equal AuditLog::GENESIS, chain.first.prev_hash
    assert_equal chain[0].chain_hash, chain[1].prev_hash
    assert_equal chain[1].chain_hash, chain[2].prev_hash
    assert_equal chain[0].compute_chain_hash, chain[0].chain_hash
  end

  test "the verification screen reports an untouched chain as intact" do
    owner = create_user(username: "king", role: "owner")
    entries(4)

    sign_in(owner)
    get admin_audit_verify_path

    assert_response :success
    assert_match(/Chain intact/, response.body)
    assert_match(/Audit integrity/, response.body)
  end

  test "editing an entry's contents breaks the chain and is reported" do
    owner = create_user(username: "king", role: "owner")
    entries(3)
    AuditLog.chained.order(:seq).first.update_column(:detail, "quietly rewritten")

    result = AuditLog.verify_chain
    refute result[:intact]
    assert_equal 1, result[:broken].size
    assert_match(/no longer match the digest/, result[:broken].first[:problems].join)

    sign_in(owner)
    get admin_audit_verify_path
    assert_response :success
    assert_match(/Chain broken/, response.body)
    assert_match(/no longer match the digest/, response.body)
  end

  test "deleting an entry breaks the chain because the next one names it" do
    owner = create_user(username: "king", role: "owner")
    entries(3)
    AuditLog.chained.order(:seq).second.delete

    result = AuditLog.verify_chain
    refute result[:intact]
    assert_equal 2, result[:length]
    assert_equal 1, result[:broken].size
    assert_match(/missing or reordered/, result[:broken].first[:problems].join)
  end

  test "entries written before the chain existed are reported, not called broken" do
    owner = create_user(username: "king", role: "owner")
    legacy = AuditLog.create!(actor: nil, action: "legacy.action", target: "user:2", detail: "old")
    assert_nil legacy.seq

    result = AuditLog.verify_chain
    assert result[:intact]
    assert_equal 1, result[:unhashed]

    sign_in(owner)
    get admin_audit_verify_path
    assert_response :success
    assert_match(/Unsealed entries/, response.body)
  end

  test "the verification screen is refused without the audit grant" do
    moderator = create_user(username: "mod", role: "moderator")
    entries(2)

    sign_in(moderator)
    get admin_audit_verify_path
    assert_redirected_to admin_root_path
  end

  test "a recorded admin action lands in the chain" do
    owner = create_user(username: "king", role: "owner")
    member = create_user(username: "member")

    sign_in(owner)
    post admin_user_warn_path(member), params: { category: "abuse", reason: "Be nicer" }
    assert_response :redirect

    entry = AuditLog.chained.order(seq: :desc).first
    assert_equal "users.warn", entry.action
    assert entry.chained?
    assert_equal entry.compute_chain_hash, entry.chain_hash
  end
end
