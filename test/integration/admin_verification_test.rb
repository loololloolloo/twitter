require "test_helper"

# Covers the verification request queue and its separation-of-duties rule.
# Approving a request is what grants the verified badge, so the decision is the
# grant: there is no second toggle to disagree with it. These tests check the
# queue reads the requester's account signals next to the controls, that a
# member cannot review their own request, and that only a permitted, different
# operator can record a decision.
class AdminVerificationTest < ActionDispatch::IntegrationTest
  def filed_request(user:, category: "individual", state: "pending", **attrs)
    VerificationRequest.create!(
      user: user,
      category: category,
      body: "I am covered by the local paper.",
      state: state,
      **attrs
    )
  end

  test "the owner sees the pending queue with the requester's signals" do
    owner = create_user(username: "king", role: "owner")
    member = create_user(username: "member")
    Tweet.create!(user: member, body: "hello")
    filed_request(user: member)

    sign_in(owner)
    get admin_verification_path

    assert_response :success
    assert_match(/Verification requests/, response.body)
    assert_match(/@member/, response.body)
    assert_match(/I am covered by the local paper\./, response.body)
    # The signals the decision is read against, not just the member's wording.
    assert_match(/Account age/, response.body)
    assert_match(/Followers/, response.body)
    assert_match(/Standing warnings/, response.body)
    assert_match(/Open reports/, response.body)
  end

  test "the applicant is barred from reviewing their own request and told why" do
    applicant = create_user(username: "applicant", role: "owner")
    filed_request(user: applicant)

    sign_in(applicant)
    get admin_verification_path

    assert_response :success
    assert_match(/You cannot decide this request/, response.body)
    assert_match(/You filed this request/, response.body)
    assert_no_match(/Record decision/, response.body)
  end

  test "a barred operator cannot decide through a direct request" do
    applicant = create_user(username: "applicant", role: "owner")
    request = filed_request(user: applicant)

    sign_in(applicant)
    post admin_verification_decide_path(request), params: { decision: "approved" }

    assert_redirected_to admin_verification_path
    assert_equal "pending", request.reload.state
    assert_nil request.reviewed_by_id
    refute applicant.reload.is_verified
    refute AuditLog.exists?(action: "verification.decide")
  end

  test "the model refuses a self-review even without the controller guard" do
    applicant = create_user(username: "applicant", role: "owner")
    request = filed_request(user: applicant)

    assert_raises(ArgumentError) do
      request.decide!(decision: "approved", actor: applicant)
    end
    assert_equal "pending", request.reload.state
    refute applicant.reload.is_verified
  end

  test "a different operator approving grants the badge and is recorded" do
    applicant = create_user(username: "applicant")
    reviewer = create_user(username: "reviewer", role: "owner")
    request = filed_request(user: applicant, category: "journalist")

    sign_in(reviewer)
    post admin_verification_decide_path(request), params: { decision: "approved" }

    assert_redirected_to admin_verification_path
    request.reload
    assert_equal "approved", request.state
    assert_equal reviewer.id, request.reviewed_by_id
    assert request.decided_at.present?
    # The decision is the grant: the badge exists because of it.
    assert applicant.reload.is_verified

    assert AuditLog.exists?(action: "verification.decide", target: "user:#{applicant.id}")
  end

  test "approving notifies the member the badge was granted" do
    applicant = create_user(username: "applicant")
    reviewer = create_user(username: "reviewer", role: "owner")
    request = filed_request(user: applicant)

    sign_in(reviewer)
    post admin_verification_decide_path(request), params: { decision: "approved" }

    note = applicant.notifications.last
    assert note.present?, "the member should be told the outcome"
    assert_equal "admin", note.kind
    assert_match(/approved/, note.body)
  end

  test "a denial requires a reason and is carried to the member" do
    applicant = create_user(username: "applicant")
    reviewer = create_user(username: "reviewer", role: "owner")
    request = filed_request(user: applicant)

    sign_in(reviewer)

    post admin_verification_decide_path(request), params: { decision: "denied", note: "" }
    assert_redirected_to admin_verification_path
    assert_equal "pending", request.reload.state

    post admin_verification_decide_path(request), params: {
      decision: "denied", note: "Not notable outside your own site"
    }
    request.reload
    assert_equal "denied", request.state
    refute applicant.reload.is_verified
    assert_equal "Not notable outside your own site", request.decision_note

    note = applicant.notifications.last
    assert_match(/denied/, note.body)
    assert_match(/Not notable outside your own site/, note.body)
  end

  test "a request is not decided twice" do
    applicant = create_user(username: "applicant")
    first = create_user(username: "first", role: "owner")
    second = create_user(username: "second", role: "owner")
    request = filed_request(user: applicant)

    sign_in(first)
    post admin_verification_decide_path(request), params: { decision: "denied", note: "No" }
    assert_equal "denied", request.reload.state

    sign_in(second)
    post admin_verification_decide_path(request), params: { decision: "approved" }

    assert_redirected_to admin_verification_path
    assert_equal "denied", request.reload.state
    assert_equal first.id, request.reviewed_by_id
    refute applicant.reload.is_verified
  end

  test "an unknown outcome is refused" do
    applicant = create_user(username: "applicant")
    reviewer = create_user(username: "reviewer", role: "owner")
    request = filed_request(user: applicant)

    sign_in(reviewer)
    post admin_verification_decide_path(request), params: { decision: "maybe" }

    assert_redirected_to admin_verification_path
    assert_equal "pending", request.reload.state
  end

  test "an operator without verification.decide cannot decide" do
    applicant = create_user(username: "applicant")
    member = create_user(username: "member")
    request = filed_request(user: applicant)

    sign_in(member)
    post admin_verification_decide_path(request), params: { decision: "approved" }

    assert_equal "pending", request.reload.state
    refute applicant.reload.is_verified
  end

  test "a moderator holds the verification grants and can work the queue" do
    moderator = create_user(username: "mod", role: "moderator")
    role = Role.find_by!(name: "moderator")
    assert role.permissions.exists?(key: "verification.view")
    assert role.permissions.exists?(key: "verification.decide")

    sign_in(moderator)
    get admin_verification_path
    assert_response :success
  end

  test "the queue filters by state and counts each tab" do
    owner = create_user(username: "king", role: "owner")
    applicant = create_user(username: "applicant")
    reviewer = create_user(username: "reviewer", role: "owner")
    filed_request(user: applicant)
    filed_request(user: applicant, state: "approved", reviewed_by: reviewer,
                  decision_note: "", decided_at: Time.current)

    sign_in(owner)

    get admin_verification_path
    # The default view is the pending queue, so only the open request shows.
    assert_match(/I am covered by the local paper\./, response.body)
    assert_match(/state-count">1</, response.body)

    get admin_verification_path(state: "approved")
    assert_match(/Approved - badge granted/, response.body)
  end

  test "the owner account cannot be granted a badge by another operator" do
    owner = create_user(username: "king", role: "owner")
    reviewer = create_user(username: "reviewer", role: "owner")
    # A request filed against the owner account, decided by a different
    # operator: the separation-of-duties rule allows it, the owner guard does
    # not.
    request = filed_request(user: owner)

    sign_in(reviewer)
    post admin_verification_decide_path(request), params: { decision: "approved" }

    assert_redirected_to admin_verification_path
    assert_equal "pending", request.reload.state
    refute owner.reload.is_verified
  end

  test "a member files a request from settings and it lands in the queue" do
    member = create_user(username: "member")
    sign_in(member)

    post verification_requests_path, params: {
      category: "business", body: "We are the official city transit account."
    }

    assert_redirected_to settings_path
    request = member.verification_requests.last
    assert request.present?
    assert_equal "pending", request.state
    assert_equal "business", request.category
    assert_equal "We are the official city transit account.", request.body
    refute member.reload.is_verified, "filing a request must not grant the badge"
  end

  test "a member cannot file a second request while one is pending" do
    member = create_user(username: "member")
    filed_request(user: member)

    sign_in(member)
    post verification_requests_path, params: { category: "individual", body: "Again" }

    assert_redirected_to settings_path
    assert_equal 1, member.verification_requests.count
  end

  test "an incomplete or unknown request is refused" do
    member = create_user(username: "member")
    sign_in(member)

    post verification_requests_path, params: { category: "individual", body: "  " }
    post verification_requests_path, params: { category: "nonsense", body: "Hi" }

    assert_equal 0, member.verification_requests.count
  end

  test "an already verified member is not queued again" do
    member = create_user(username: "member", is_verified: true)
    sign_in(member)

    post verification_requests_path, params: { category: "individual", body: "Please" }

    assert_redirected_to settings_path
    assert_equal 0, member.verification_requests.count
  end
end
