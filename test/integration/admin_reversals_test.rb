require "test_helper"

# Covers reversing a moderation action. A reversal lifts a sanction without
# deleting anything: the original action stays in the history and the decision
# to undo it is appended next to it, attributed and reasoned. The rule that
# matters is separation of duties - the operator who imposed a sanction may not
# be the one who reverses it - so these tests check both the happy path and the
# refusals, and that a barred operator is told why rather than shown a form.
class AdminReversalsTest < ActionDispatch::IntegrationTest
  def ban_user(actor:, target:, reason: "Repeated spam", duration: "7d")
    sign_in(actor)
    post admin_user_ban_path(target), params: { reason: reason, duration: duration }
    assert_response :redirect, "ban by @#{actor.username} did not succeed"
  end

  test "a ban imposed by another operator offers a reversal form" do
    imposer = create_user(username: "issuer", role: "owner")
    reviewer = create_user(username: "reviewer", role: "owner")
    member = create_user(username: "member")
    ban_user(actor: imposer, target: member)

    sign_in(reviewer)
    get admin_user_path(member)

    assert_response :success
    assert_match(/Reverse a moderation action/, response.body)
    assert_match(/imposed by @issuer/, response.body)
    assert_match(/Reverse ban/, response.body)
  end

  test "a reversal clears the ban and records the decision without deleting the sanction" do
    imposer = create_user(username: "issuer", role: "owner")
    reviewer = create_user(username: "reviewer", role: "owner")
    member = create_user(username: "member")
    ban_user(actor: imposer, target: member)
    assert member.reload.is_banned

    sign_in(reviewer)
    post admin_user_reverse_path(member), params: { source: "ban", reason: "Appeal evidence" }

    assert_redirected_to admin_user_path(member)
    member.reload
    refute member.is_banned
    assert_equal "", member.ban_reason

    reversal = member.moderation_reversals.last
    assert_equal "ban", reversal.source
    assert_equal reviewer.id, reversal.actor_id
    assert_equal imposer.id, reversal.imposed_by_id
    assert_equal "Appeal evidence", reversal.reason
    assert_equal "users.ban", reversal.action

    # The original sanction's audit entry survives, and the reversal is its own
    # entry next to it.
    assert AuditLog.exists?(action: "users.ban", target: "user:#{member.id}")
    assert AuditLog.exists?(action: "users.reverse", target: "user:#{member.id}")
  end

  test "the operator who imposed the sanction is barred and told why" do
    imposer = create_user(username: "issuer", role: "owner")
    member = create_user(username: "member")
    ban_user(actor: imposer, target: member)

    sign_in(imposer)
    get admin_user_path(member)

    assert_response :success
    assert_match(/You imposed this ban/, response.body)
    assert_match(/a different operator has to reverse it/, response.body)
    # No reversal form is rendered for a barred operator.
    assert_no_match(/Reverse ban/, response.body)
  end

  test "a barred operator cannot reverse through a direct request" do
    imposer = create_user(username: "issuer", role: "owner")
    member = create_user(username: "member")
    ban_user(actor: imposer, target: member)

    sign_in(imposer)
    post admin_user_reverse_path(member), params: { source: "ban", reason: "Mine" }

    assert_redirected_to admin_user_path(member)
    assert member.reload.is_banned
    assert_equal 0, member.moderation_reversals.count
    refute AuditLog.exists?(action: "users.reverse")
  end

  test "the model refuses a reversal by the imposer even outside the screen" do
    imposer = create_user(username: "issuer", role: "owner")
    member = create_user(username: "member")

    reversal = ModerationReversal.new(
      user: member, actor: imposer, imposed_by: imposer,
      source: "ban", source_id: 0, action: "users.ban", reason: "Mine"
    )

    refute reversal.valid?
    assert_includes reversal.errors[:actor], "cannot reverse a sanction they imposed"
  end

  test "a suspension can be reversed" do
    imposer = create_user(username: "issuer", role: "owner")
    reviewer = create_user(username: "reviewer", role: "owner")
    member = create_user(username: "member")

    sign_in(imposer)
    post admin_user_suspend_path(member)
    assert member.reload.is_suspended

    sign_in(reviewer)
    post admin_user_reverse_path(member), params: { source: "suspension", reason: "Reinstated after review" }

    assert_redirected_to admin_user_path(member)
    refute member.reload.is_suspended
    assert_equal "suspension", member.moderation_reversals.last.source
  end

  test "reversing a warning expires it rather than destroying it" do
    imposer = create_user(username: "issuer", role: "owner")
    reviewer = create_user(username: "reviewer", role: "owner")
    member = create_user(username: "member")

    sign_in(imposer)
    post admin_user_warn_path(member), params: { category: "spam", reason: "Duplicate links" }
    warning = member.user_warnings.last
    assert warning.active?

    sign_in(reviewer)
    post admin_user_reverse_path(member), params: { source: "warning", reason: "Not a violation" }

    assert_redirected_to admin_user_path(member)
    warning.reload
    refute warning.active?
    assert_equal 1, member.user_warnings.count, "the warning row must survive the reversal"
    assert_equal "warning", member.moderation_reversals.last.source
    assert_equal warning.id, member.moderation_reversals.last.source_id
  end

  test "a reversal with no reason is refused" do
    imposer = create_user(username: "issuer", role: "owner")
    reviewer = create_user(username: "reviewer", role: "owner")
    member = create_user(username: "member")
    ban_user(actor: imposer, target: member)

    sign_in(reviewer)
    post admin_user_reverse_path(member), params: { source: "ban", reason: "  " }

    assert_redirected_to admin_user_path(member)
    assert member.reload.is_banned
    assert_equal 0, member.moderation_reversals.count
  end

  test "an unknown source is refused" do
    owner = create_user(username: "king", role: "owner")
    member = create_user(username: "member")

    sign_in(owner)
    post admin_user_reverse_path(member), params: { source: "exile", reason: "Nope" }

    assert_redirected_to admin_user_path(member)
    assert_equal 0, member.moderation_reversals.count
  end

  test "reversing a sanction that is not in effect is refused" do
    owner = create_user(username: "king", role: "owner")
    member = create_user(username: "member")

    sign_in(owner)
    post admin_user_reverse_path(member), params: { source: "ban", reason: "Nothing to lift" }

    assert_redirected_to admin_user_path(member)
    assert_equal 0, member.moderation_reversals.count
  end

  test "an operator cannot reverse a sanction on their own account" do
    boss = create_user(username: "boss", role: "owner")
    victim = create_user(username: "victim", role: "admin")

    # The boss warns the admin, so the sanction was imposed by a different
    # operator and the only remaining bar is the self-account rule. A warning
    # is used rather than a ban because a banned account cannot sign in to
    # attempt the reversal.
    sign_in(boss)
    post admin_user_warn_path(victim), params: { category: "spam", reason: "Links", duration: "none" }
    assert victim.reload.user_warnings.last.active?

    sign_in(victim)
    post admin_user_reverse_path(victim), params: { source: "warning", reason: "me" }

    assert_redirected_to admin_user_path(victim)
    assert victim.reload.user_warnings.last.active?
    assert_equal 0, victim.moderation_reversals.count
  end

  test "a moderator without users.reverse cannot reverse and sees no controls" do
    imposer = create_user(username: "issuer", role: "owner")
    moderator = create_user(username: "mod", role: "moderator")
    member = create_user(username: "member")
    ban_user(actor: imposer, target: member)

    sign_in(moderator)
    get admin_user_path(member)
    assert_response :success
    assert_match(/Your role cannot reverse moderation actions/, response.body)
    assert_no_match(/Reverse ban/, response.body)

    post admin_user_reverse_path(member), params: { source: "ban", reason: "Nope" }
    assert_response :redirect
    assert member.reload.is_banned
    assert_equal 0, member.moderation_reversals.count
  end

  test "the history shows the reversal beside the original sanction" do
    imposer = create_user(username: "issuer", role: "owner")
    reviewer = create_user(username: "reviewer", role: "owner")
    member = create_user(username: "member")
    ban_user(actor: imposer, target: member)

    sign_in(reviewer)
    post admin_user_reverse_path(member), params: { source: "ban", reason: "Evidence did not hold" }

    get admin_user_path(member)
    assert_response :success
    history = response.body[/<ol class="mod-history">.*?<\/ol>/m]
    assert history.present?, "the moderation history should render"
    assert_match(/Ban changed/, history)
    assert_match(/Reversed ban/, history)
    assert_match(/reversal #\d+/, history)
  end
end
