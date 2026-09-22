require "test_helper"

# The report queue used to be worked strictly oldest-first, which spends
# operator attention on whichever report happens to be oldest rather than on
# whichever account is actually dangerous. These tests cover the computed
# priority, the ordering it produces, and the two things that keep it honest:
# the factors are visible, and a low-risk row is still resolvable normally.
class AdminRiskTriageTest < ActionDispatch::IntegrationTest
  test "a higher-risk report sorts above an older, milder one" do
    owner = create_user(username: "king", role: "owner")
    mild = create_user(username: "mild")
    acute = create_user(username: "acute")

    old_mild = Report.create!(user: mild, category: "spam", detail: "old advertising")
    old_mild.update_column(:created_at, 10.days.ago)
    Report.create!(user: acute, category: "self_harm", detail: "urgent")

    # Give the acute account the danger signals a real high-risk row carries.
    acute.update!(requires_review: true, is_suspended: true)
    UserWarning.create!(user: acute, actor: owner, category: "abuse", reason: "threats")

    sign_in(owner)
    get admin_reports_path(state: "open")

    assert_response :success
    assert response.body.index("@acute") < response.body.index("@mild"),
           "the newer high-risk report should be listed before the older mild one"
  end

  test "the ordering factors are shown next to the score" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")
    Report.create!(user: target, category: "hate", detail: "slur")

    sign_in(owner)
    get admin_reports_path(state: "open")

    assert_response :success
    assert_match(/risk/, response.body)
    assert_match(/Open reports/, response.body)
    assert_match(/Grave category/, response.body)
    assert_match(/Work soon|Work now|Normal/, response.body)
  end

  test "oldest-first remains available for a backlog that predates the score" do
    owner = create_user(username: "king", role: "owner")
    mild = create_user(username: "mild")
    acute = create_user(username: "acute")

    older = Report.create!(user: mild, category: "spam")
    older.update_column(:created_at, 10.days.ago)
    Report.create!(user: acute, category: "self_harm")
    acute.update!(is_suspended: true)

    sign_in(owner)
    get admin_reports_path(state: "open", sort: "oldest")

    assert_response :success
    assert response.body.index("@mild") < response.body.index("@acute")
  end

  test "a role without reports.view never sees the queue or its scores" do
    member = create_user(username: "member", role: "user")
    Report.create!(user: member, category: "abuse")

    sign_in(member)
    get admin_reports_path

    assert_redirected_to home_path
  end

  test "a low-risk report is still resolvable through the ordinary decision" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")
    report = Report.create!(user: target, category: "spam")

    sign_in(owner)
    post admin_report_resolve_path(report), params: { decision: "dismissed", note: "noise" }

    assert_equal "dismissed", report.reload.state
    assert_equal "noise", report.resolution_note
  end
end
