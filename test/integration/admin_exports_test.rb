require "test_helper"

# Covers the per-account evidence export. An export is a disclosure rather than
# a read, so it is its own grant, it demands a reason, and it leaves two
# records: a durable `data_exports` row answering "who pulled what and why" for
# a legal hold, and an entry in the tamper-evident audit trail. These tests
# check the file's contents, that the reason is enforced, that a re-download
# does not double-count the disclosure, and that an operator without the grant
# is turned away.
class AdminExportsTest < ActionDispatch::IntegrationTest
  def export_account(target, reason: "Legal hold 2026-114")
    get admin_export_path(target), params: { reason: reason }
  end

  test "the queue lists past exports with the operator and reason" do
    owner = create_user(username: "king", role: "owner")
    member = create_user(username: "member")
    DataExport.create!(user: member, actor: owner, reason: "Support ticket #8821",
                       post_count: 2, enforcement_count: 1)

    sign_in(owner)
    get admin_exports_path

    assert_response :success
    assert_match(/Evidence export/, response.body)
    assert_match(/@member/, response.body)
    assert_match(/@king/, response.body)
    assert_match(/Support ticket #8821/, response.body)
  end

  test "exporting builds a file with the account record, posts and history" do
    owner = create_user(username: "king", role: "owner")
    member = create_user(username: "member", bio: "here for the timeline")
    tweet = Tweet.create!(user: member, body: "the post under review")
    UserWarning.create!(user: member, actor: owner, category: "abuse", reason: "Rude replies")
    AuditLog.record(actor: owner, action: "users.ban", target: "user:#{member.id}",
                    detail: "banned permanently")

    sign_in(owner)
    export_account(member, reason: "Legal hold 2026-114")

    assert_response :success
    assert_equal "text/plain", response.media_type
    body = response.body
    assert_match(/ACCOUNT EVIDENCE EXPORT/, body)
    assert_match(/@member \(user ##{member.id}\)/, body)
    assert_match(/reason:\s+Legal hold 2026-114/, body)
    assert_match(/the post under review/, body)
    assert_match(/users\.ban/, body)
    assert_match(/Rude replies/, body)
    assert_match(/anonymise|disclosure of personal data/i, body)
    assert_match(/post ##{tweet.id}/, body)
  end

  test "exporting records the disclosure and audits it" do
    owner = create_user(username: "king", role: "owner")
    member = create_user(username: "member")
    Tweet.create!(user: member, body: "one")
    Tweet.create!(user: member, body: "two")

    sign_in(owner)
    assert_difference -> { DataExport.count } => 1 do
      export_account(member, reason: "Data request DS-77")
    end

    record = DataExport.order(:id).last
    assert_equal member.id, record.user_id
    assert_equal owner.id, record.actor_id
    assert_equal "Data request DS-77", record.reason
    assert_equal 2, record.post_count

    entry = AuditLog.recent.find_by(action: "exports.download")
    assert_not_nil entry
    assert_equal "user:#{member.id}", entry.target
    assert_match(/Data request DS-77/, entry.detail)
  end

  test "the reason is required before a file is produced" do
    owner = create_user(username: "king", role: "owner")
    member = create_user(username: "member")

    sign_in(owner)
    assert_no_difference -> { DataExport.count } do
      export_account(member, reason: "   ")
    end

    assert_response :redirect
    assert_match(/reason is required/i, flash[:alert].to_s)
  end

  test "an over-long reason is refused" do
    owner = create_user(username: "king", role: "owner")
    member = create_user(username: "member")

    sign_in(owner)
    assert_no_difference -> { DataExport.count } do
      export_account(member, reason: "x" * (DataExport::MAX_REASON + 1))
    end

    assert_response :redirect
    assert_match(/limited to #{DataExport::MAX_REASON}/, flash[:alert].to_s)
  end

  test "a missing account answers with the app's not-found screen" do
    owner = create_user(username: "king", role: "owner")
    sign_in(owner)

    get admin_export_path(999_999), params: { reason: "Legal hold" }
    assert_response :not_found
  end

  test "re-downloading does not record a second disclosure but is audited" do
    owner = create_user(username: "king", role: "owner")
    member = create_user(username: "member")
    record = DataExport.create!(user: member, actor: owner, reason: "Legal hold 2026-114",
                                post_count: 0, enforcement_count: 0)

    sign_in(owner)
    assert_no_difference -> { DataExport.count } do
      get admin_export_download_path(record)
    end

    assert_response :success
    assert_match(/Legal hold 2026-114/, response.body)
    assert AuditLog.recent.exists?(action: "exports.redownload",
                                   target: "user:#{member.id}")
  end

  test "an operator without the grant cannot export or reach the queue" do
    moderator = create_user(username: "mod", role: "moderator")
    member = create_user(username: "member")

    sign_in(moderator)
    get admin_exports_path
    assert_response :redirect
    assert_match(/exports\.run permission/, flash[:alert].to_s)

    assert_no_difference -> { DataExport.count } do
      export_account(member)
    end
    assert_response :redirect
    assert_match(/exports\.run permission/, flash[:alert].to_s)
  end

  test "the owner account can be exported because an export only reads" do
    owner = create_user(username: "king", role: "owner")
    create_user(username: "admin", role: "admin")

    sign_in(owner)
    assert_difference -> { DataExport.count } => 1 do
      export_account(owner, reason: "Disclosure to the account itself")
    end
    assert_response :success
    assert_equal owner.id, DataExport.order(:id).last.user_id
  end
end
