require "test_helper"

# Covers the case queue: one investigation standing in for a pile of reports,
# and the separation-of-duties rule on its decision. A case is opened by the
# operator who spotted the cluster, so that operator may not decide it. These
# tests check the queue reads correctly, that reports link and cannot be linked
# twice, that the barred operator is told why rather than shown a refusing
# form, and that only a different, permitted operator records the decision.
class AdminCasesTest < ActionDispatch::IntegrationTest
  def open_case(opened_by:, user:, title: "Coordinated spam", state: "open", **attrs)
    ModerationCase.create!(
      user: user,
      title: title,
      summary: "Five reports in an hour.",
      opened_by: opened_by,
      state: state,
      **attrs
    )
  end

  def link_report(moderation_case, report, linked_by: nil)
    CaseLink.create!(moderation_case: moderation_case, report: report, linked_by: linked_by)
  end

  test "the owner sees the open cases queue" do
    owner = create_user(username: "king", role: "owner")
    member = create_user(username: "member")
    open_case(opened_by: owner, user: member)

    sign_in(owner)
    get admin_cases_path

    assert_response :success
    assert_match(/Cases/, response.body)
    assert_match(/Coordinated spam/, response.body)
    assert_match(/@member/, response.body)
    assert_match(/by @king/, response.body)
  end

  test "an operator opens a case built from a report" do
    owner = create_user(username: "king", role: "owner")
    member = create_user(username: "member")
    report = Report.create!(user: member, reporter: owner, category: "spam", detail: "bot")

    sign_in(owner)
    post admin_cases_path, params: {
      user_id: member.id, title: "Bot network", summary: "Same links",
      report_ids: [ report.id ]
    }

    moderation_case = ModerationCase.last
    assert_redirected_to admin_case_path(moderation_case)
    assert_equal member.id, moderation_case.user_id
    assert_equal "Bot network", moderation_case.title
    assert_equal owner.id, moderation_case.opened_by_id
    assert_equal "open", moderation_case.state
    assert_equal [ report.id ], moderation_case.case_links.pluck(:report_id)
    assert_equal owner.id, moderation_case.case_links.first.linked_by_id
    assert AuditLog.exists?(action: "cases.open", target: "case:#{moderation_case.id}")
  end

  test "a case needs a subject and a title" do
    owner = create_user(username: "king", role: "owner")
    member = create_user(username: "member")

    sign_in(owner)
    post admin_cases_path, params: { title: "No subject" }
    assert_redirected_to admin_cases_path
    assert_equal 0, ModerationCase.count

    post admin_cases_path, params: { user_id: member.id, title: "  " }
    assert_redirected_to admin_user_path(member)
    assert_equal 0, ModerationCase.count
  end

  test "a report cannot be linked to two cases" do
    owner = create_user(username: "king", role: "owner")
    member = create_user(username: "member")
    report = Report.create!(user: member, reporter: owner, category: "spam", detail: "bot")
    first = open_case(opened_by: owner, user: member)
    second = open_case(opened_by: owner, user: member, title: "Other")
    link_report(first, report)

    assert_raises(ActiveRecord::RecordInvalid) do
      CaseLink.create!(moderation_case: second, report: report)
    end
  end

  test "an operator links reports to an existing case and the link is audited" do
    owner = create_user(username: "king", role: "owner")
    member = create_user(username: "member")
    report = Report.create!(user: member, reporter: owner, category: "spam", detail: "bot")
    moderation_case = open_case(opened_by: owner, user: member)

    sign_in(owner)
    post admin_case_link_path(moderation_case), params: { report_ids: [ report.id ] }

    assert_redirected_to admin_case_path(moderation_case)
    assert_equal 1, moderation_case.reload.report_count
    assert AuditLog.exists?(action: "cases.link", target: "case:#{moderation_case.id}")
  end

  test "re-linking the same report is a no-op rather than a duplicate" do
    owner = create_user(username: "king", role: "owner")
    member = create_user(username: "member")
    report = Report.create!(user: member, reporter: owner, category: "spam", detail: "bot")
    moderation_case = open_case(opened_by: owner, user: member)
    link_report(moderation_case, report)

    sign_in(owner)
    post admin_case_link_path(moderation_case), params: { report_ids: [ report.id ] }

    assert_redirected_to admin_case_path(moderation_case)
    assert_equal 1, moderation_case.reload.report_count
  end

  test "the operator who opened the case is barred and told why" do
    opener = create_user(username: "opener", role: "owner")
    member = create_user(username: "member")
    moderation_case = open_case(opened_by: opener, user: member)

    sign_in(opener)
    get admin_case_path(moderation_case)

    assert_response :success
    # The screen states the bar rather than hiding the controls silently.
    assert_match(/You cannot decide this case/, response.body)
    assert_match(/You opened this case; it has to be decided by someone else\./, response.body)
    assert_no_match(/Record decision/, response.body)
  end

  test "a barred operator cannot decide through a direct request" do
    opener = create_user(username: "opener", role: "owner")
    member = create_user(username: "member")
    moderation_case = open_case(opened_by: opener, user: member)

    sign_in(opener)
    post admin_case_decide_path(moderation_case), params: { decision: "actioned", note: "Mine" }

    assert_redirected_to admin_case_path(moderation_case)
    assert_equal "open", moderation_case.reload.state
    assert_nil moderation_case.decided_by_id
    refute AuditLog.exists?(action: "cases.decide")
  end

  test "a different operator decides and the decision is recorded" do
    opener = create_user(username: "opener", role: "owner")
    decider = create_user(username: "decider", role: "owner")
    member = create_user(username: "member")
    moderation_case = open_case(opened_by: opener, user: member)

    sign_in(decider)
    post admin_case_decide_path(moderation_case), params: {
      decision: "actioned", note: "All five were the same bot network"
    }

    assert_redirected_to admin_case_path(moderation_case)
    moderation_case.reload
    assert_equal "actioned", moderation_case.state
    assert_equal decider.id, moderation_case.decided_by_id
    assert_equal "All five were the same bot network", moderation_case.decision_note
    assert moderation_case.decided_at.present?

    assert AuditLog.exists?(action: "cases.decide", target: "case:#{moderation_case.id}")
  end

  test "a case needs an outcome and a rationale to be decided" do
    opener = create_user(username: "opener", role: "owner")
    decider = create_user(username: "decider", role: "owner")
    member = create_user(username: "member")
    moderation_case = open_case(opened_by: opener, user: member)

    sign_in(decider)
    post admin_case_decide_path(moderation_case), params: { decision: "maybe", note: "?" }
    assert_equal "open", moderation_case.reload.state

    post admin_case_decide_path(moderation_case), params: { decision: "actioned", note: "  " }
    assert_equal "open", moderation_case.reload.state
  end

  test "a case is not decided twice" do
    opener = create_user(username: "opener", role: "owner")
    decider = create_user(username: "decider", role: "owner")
    other = create_user(username: "other", role: "owner")
    member = create_user(username: "member")
    moderation_case = open_case(opened_by: opener, user: member)

    sign_in(decider)
    post admin_case_decide_path(moderation_case), params: { decision: "dismissed", note: "Nothing there" }
    assert_equal "dismissed", moderation_case.reload.state

    sign_in(other)
    post admin_case_decide_path(moderation_case), params: { decision: "actioned", note: "Changed mind" }

    assert_redirected_to admin_case_path(moderation_case)
    assert_equal "dismissed", moderation_case.reload.state
    assert_equal decider.id, moderation_case.decided_by_id
  end

  test "a decided case takes no new reports" do
    opener = create_user(username: "opener", role: "owner")
    decider = create_user(username: "decider", role: "owner")
    member = create_user(username: "member")
    report = Report.create!(user: member, reporter: opener, category: "spam", detail: "bot")
    moderation_case = open_case(opened_by: opener, user: member, state: "actioned",
                                decided_by: decider, decision_note: "Done",
                                decided_at: Time.current)

    sign_in(decider)
    post admin_case_link_path(moderation_case), params: { report_ids: [ report.id ] }

    assert_redirected_to admin_case_path(moderation_case)
    assert_equal 0, moderation_case.reload.report_count
  end

  test "the model refuses a barred operator even without the controller guard" do
    opener = create_user(username: "opener", role: "owner")
    member = create_user(username: "member")
    moderation_case = open_case(opened_by: opener, user: member)

    refute moderation_case.decidable_by?(opener)
    assert_match(/You opened this case/, moderation_case.bar_reason(opener))
    assert_raises(ArgumentError) do
      moderation_case.decide!(decision: "actioned", actor: opener, note: "Should not record")
    end
    assert_equal "open", moderation_case.reload.state
  end

  test "a member without the admin panel cannot open or decide a case" do
    opener = create_user(username: "opener", role: "owner")
    member = create_user(username: "member")
    moderation_case = open_case(opened_by: opener, user: member)

    sign_in(member)
    post admin_case_decide_path(moderation_case), params: { decision: "actioned", note: "Nope" }

    assert_redirected_to home_path
    assert_equal "open", moderation_case.reload.state
  end

  test "a moderator holds the cases grants and can work the queue" do
    moderator = create_user(username: "mod", role: "moderator")
    moderator_role = Role.find_by!(name: "moderator")
    %w[cases.view cases.open cases.link cases.decide].each do |key|
      assert moderator_role.permissions.exists?(key: key), "moderator is missing #{key}"
    end

    sign_in(moderator)
    get admin_cases_path
    assert_response :success
  end

  test "the queue filters by state and counts each tab" do
    opener = create_user(username: "opener", role: "owner")
    decider = create_user(username: "decider", role: "owner")
    member = create_user(username: "member")
    open_case(opened_by: opener, user: member, title: "Still open")
    open_case(opened_by: opener, user: member, title: "Already done", state: "dismissed",
              decided_by: decider, decision_note: "Nothing there", decided_at: Time.current)

    sign_in(opener)

    get admin_cases_path
    # The default view is the open queue.
    assert_match(/Still open/, response.body)
    assert_no_match(/Already done/, response.body)

    get admin_cases_path(state: "dismissed")
    assert_response :success
    assert_match(/Already done/, response.body)

    get admin_cases_path(state: "all")
    assert_response :success
    assert_match(/Still open/, response.body)
    assert_match(/Already done/, response.body)
  end

  test "the case page shows its linked reports and their state" do
    opener = create_user(username: "opener", role: "owner")
    member = create_user(username: "member")
    report = Report.create!(user: member, reporter: opener, category: "hate", detail: "slur")
    moderation_case = open_case(opened_by: opener, user: member)
    link_report(moderation_case, report)

    sign_in(opener)
    get admin_case_path(moderation_case)

    assert_response :success
    assert_match(/Linked reports/, response.body)
    assert_match(/Hateful conduct/, response.body)
    assert_match(/slur/, response.body)
  end

  test "a case opened from a report preloads the report on the form" do
    owner = create_user(username: "king", role: "owner")
    member = create_user(username: "member")
    report = Report.create!(user: member, reporter: owner, category: "spam", detail: "bot")

    sign_in(owner)
    get admin_cases_path(user_id: member.id, report_ids: [ report.id ])

    assert_response :success
    assert_match(/value="#{report.id}"\s+checked/, response.body)
  end
end
