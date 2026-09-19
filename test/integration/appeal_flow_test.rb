require "test_helper"

# The member-facing half of appeals: a banned account contests its ban from the
# ban screen. That screen is the only one the ban gate leaves open, so the form
# there has to work while every other route is blocked, and it can only ever
# file against the signed-in account because the request carries no id.
class AppealFlowTest < ActionDispatch::IntegrationTest
  test "a banned member can file one appeal from the ban screen" do
    member = create_user(username: "banned_one")
    member.update!(is_banned: true, ban_reason: "Spam", ban_permanent: true)

    sign_in(member)
    get banned_path
    assert_response :success
    assert_match(/Appeal this decision/, response.body)

    post appeals_path, params: { body: "Those links were not mine." }

    assert_redirected_to banned_path
    appeal = member.appeals.last
    assert appeal.present?
    assert_equal "pending", appeal.state
    assert_equal "ban", appeal.sanction_kind
    assert_equal "Spam", appeal.sanction_reason
    assert_equal "Those links were not mine.", appeal.body
  end

  test "the appeal records the operator who imposed the ban" do
    issuer = create_user(username: "issuer", role: "owner")
    member = create_user(username: "banned_two")
    member.update!(is_banned: true, ban_reason: "Evading", ban_permanent: true)
    AuditLog.create!(actor: issuer, action: "users.ban",
                     target: "user:#{member.id}", detail: "banned for permanent: Evading")

    sign_in(member)
    post appeals_path, params: { body: "Please review." }

    assert_equal issuer.id, member.appeals.last.sanction_actor_id
  end

  test "a member cannot file a second appeal while one is open" do
    member = create_user(username: "banned_three")
    member.update!(is_banned: true, ban_reason: "Spam", ban_permanent: true)
    Appeal.create!(user: member, sanction_kind: "ban", body: "First")

    sign_in(member)
    post appeals_path, params: { body: "Second attempt" }

    assert_redirected_to banned_path
    assert_equal 1, member.appeals.count
  end

  test "an appeal with no body is refused" do
    member = create_user(username: "banned_four")
    member.update!(is_banned: true, ban_reason: "Spam", ban_permanent: true)

    sign_in(member)
    post appeals_path, params: { body: "   " }

    assert_redirected_to banned_path
    assert_equal 0, member.appeals.count
  end

  test "the ban screen reports an appeal already waiting" do
    member = create_user(username: "banned_five")
    member.update!(is_banned: true, ban_reason: "Spam", ban_permanent: true)
    Appeal.create!(user: member, sanction_kind: "ban", body: "Already sent")

    sign_in(member)
    get banned_path

    assert_response :success
    assert_match(/waiting for review/, response.body)
    assert_no_match(/Appeal this decision/, response.body)
  end

  test "only a banned member can file an appeal" do
    member = create_user(username: "fine")

    sign_in(member)
    post appeals_path, params: { body: "But I am not banned" }

    assert_redirected_to home_path
    assert_equal 0, member.appeals.count
  end
end