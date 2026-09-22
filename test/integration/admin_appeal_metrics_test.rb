require "test_helper"

# Overturn metrics on the read-only Insights screen. The number that matters to
# a moderation team is how often a second look disagrees with a first decision,
# so these pin the definition (a reversal is an overturn, a modification is
# not) and the two groupings the screen promises: by sanction and by operator.
class AdminAppealMetricsTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user(username: "metrics_owner", role: "owner")
    @member = create_user(username: "metrics_member")
    sign_in @owner
  end

  def file_appeal(state: "pending", kind: "ban", actor: nil)
    Appeal.create!(
      user: @member,
      sanction_kind: kind,
      sanction_reason: "reason",
      body: "please reconsider",
      state: state,
      decided_by: actor,
      decided_at: actor ? Time.current : nil
    )
  end

  test "overturn rate counts reversals over decided appeals and groups them" do
    # Two reversals and one upheld ban, one reversal and one upheld suspension.
    file_appeal(state: "reversed", actor: @owner)
    file_appeal(state: "reversed", actor: @owner)
    file_appeal(state: "upheld", actor: @owner)
    file_appeal(state: "reversed", kind: "suspension", actor: @member)
    file_appeal(state: "upheld", kind: "suspension", actor: @owner)
    # A pending appeal is not decided, so it stays out of the denominator.
    file_appeal(state: "pending")

    get admin_insights_path
    assert_response :success

    assert_match(/Appeal outcomes/, response.body)
    assert_match(/Overturns by sanction/, response.body)
    assert_match(/Overturns by operator/, response.body)

    # 3 of 5 decided were reversed, i.e. 60%.
    assert_match(/60%/, response.body)
    assert_match(/3 of 5 decided/, response.body)

    # The sanction table reports each kind's own rate: bans 2/3, suspensions 1/2.
    assert_match(%r{Ban</a>\s*</td>\s*<td>3</td>\s*<td>2</td>\s*<td>66%</td>}m, response.body)
    assert_match(%r{Suspension</a>\s*</td>\s*<td>2</td>\s*<td>1</td>\s*<td>50%</td>}m, response.body)

    # Both operators appear, each with their own decided/reversed counts.
    assert_match(/@metrics_owner/, response.body)
    assert_match(/@metrics_member/, response.body)
  end

  test "a modified decision is not counted as an overturn" do
    file_appeal(state: "modified", actor: @owner)
    file_appeal(state: "upheld", actor: @owner)

    get admin_insights_path
    assert_response :success

    # Nothing was reversed, so the rate is 0% rather than 50%.
    assert_match(/0%/, response.body)
    assert_match(/0 of 2 decided/, response.body)
    assert_no_match(/50%/, response.body)
  end

  test "with no decided appeals the screen says so rather than dividing by zero" do
    file_appeal(state: "pending")

    get admin_insights_path
    assert_response :success

    assert_match(/n\/a/, response.body)
    assert_match(/No appeals have been decided yet/, response.body)
  end

  test "the metrics are refused to an operator without admin access" do
    member = create_user(username: "metrics_plain")
    sign_in(member)

    get admin_insights_path
    assert_redirected_to home_path
  end
end
