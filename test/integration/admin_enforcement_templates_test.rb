require "test_helper"

# Covers enforcement macros: the canned action-and-reason combinations an
# operator applies so the same violation is described the same way every time.
# A macro is wording, not authority, so these tests check both halves - that it
# records the stored reason, and that it still clears the same guards the
# hand-written form does.
class AdminEnforcementTemplatesTest < ActionDispatch::IntegrationTest
  def create_template(attrs = {})
    EnforcementTemplate.create!({
      name: "Spam links",
      action_key: "warn",
      reason: "Posting duplicate links across replies.",
      duration: "30d",
      category: "spam"
    }.merge(attrs))
  end

  test "the owner sees the list and each macro's stored wording" do
    create_user(username: "king", role: "owner")
    create_template

    sign_in(User.find_by!(username: "king"))
    get admin_enforcement_templates_path

    assert_response :success
    assert_match(/Enforcement macros/, response.body)
    assert_match(/Spam links/, response.body)
    # The wording that will be recorded is on screen, not discovered afterwards.
    assert_match(/Posting duplicate links across replies\./, response.body)
  end

  test "managing macros is gated on users.templates, not users.warn" do
    create_template
    # The moderator role holds users.warn but not users.templates: applying a
    # macro from an account record and rewriting the shared wording are
    # different grants, so the management screen is closed to them entirely.
    moderator = create_user(username: "mod", role: "moderator")

    sign_in(moderator)
    get admin_enforcement_templates_path
    assert_redirected_to admin_root_path

    post admin_enforcement_templates_path, params: {
      name: "Sneaky", action_key: "warn", reason: "x", duration: "30d", category: "spam"
    }
    assert_redirected_to admin_root_path
    assert_nil EnforcementTemplate.find_by(name: "Sneaky")
  end

  test "creating a macro records it and audits the change" do
    owner = create_user(username: "king", role: "owner")
    sign_in(owner)

    assert_difference "EnforcementTemplate.count", 1 do
      post admin_enforcement_templates_path, params: {
        name: "Do not amplify slur",
        action_key: "warn",
        reason: "Repeated use of a slur after a prior warning.",
        duration: "30d",
        category: "abuse"
      }
    end

    template = EnforcementTemplate.find_by!(name: "Do not amplify slur")
    assert_equal "warn", template.action_key
    assert_equal "Repeated use of a slur after a prior warning.", template.reason
    assert_equal owner.id, template.created_by_id
    assert_equal "users.templates", AuditLog.last.action
  end

  test "a macro whose action takes no duration refuses one" do
    sign_in(create_user(username: "king", role: "owner"))

    post admin_enforcement_templates_path, params: {
      name: "Suspension", action_key: "suspend", reason: "x", duration: "30d"
    }

    assert_nil EnforcementTemplate.find_by(name: "Suspension")
    assert_redirected_to admin_enforcement_templates_path
  end

  test "disabling a macro keeps the row so the trail can still name it" do
    create_template(name: "Old wording")
    owner = create_user(username: "king", role: "owner")
    sign_in(owner)

    template = EnforcementTemplate.find_by!(name: "Old wording")
    post admin_enforcement_template_toggle_path(template)

    template.reload
    refute template.active
    assert EnforcementTemplate.exists?(template.id), "the row must survive so history can name it"
  end

  test "applying a warning macro records the canned reason and counts the use" do
    create_template
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")
    sign_in(owner)

    template = EnforcementTemplate.find_by!(name: "Spam links")
    assert_difference "target.user_warnings.count", 1 do
      post admin_user_apply_template_path(target), params: { template_id: template.id }
    end

    assert_redirected_to admin_user_path(target)
    warning = target.user_warnings.last
    assert_equal "Posting duplicate links across replies.", warning.reason
    assert_equal "spam", warning.category
    assert_equal owner.id, warning.actor_id
    assert_equal 1, template.reload.uses_count
  end

  test "a disabled macro cannot be applied" do
    create_template(active: false)
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")
    sign_in(owner)

    template = EnforcementTemplate.find_by!(name: "Spam links")
    post admin_user_apply_template_path(target), params: { template_id: template.id }

    assert_equal 0, target.user_warnings.count
    assert_equal 0, template.reload.uses_count
  end

  test "a macro cannot grant an action the operator does not hold" do
    # The macro names a suspension; the moderator role holds users.warn but no
    # users.suspend, so the macro must not confer the action.
    template = create_template(name: "Suspend spam", action_key: "suspend",
                               duration: "", category: "", reason: "Spam.")
    moderator = create_user(username: "mod", role: "moderator")
    target = create_user(username: "member")

    sign_in(moderator)
    post admin_user_apply_template_path(target), params: { template_id: template.id }

    refute target.reload.is_suspended, "a macro must not confer an action the operator lacks"
    assert_redirected_to admin_user_path(target)
    assert_equal 0, template.reload.uses_count
  end

  test "a ban macro cannot reach an account at or above the operator's rank" do
    template = create_template(name: "Ban spam", action_key: "ban", duration: "7d",
                               category: "", reason: "Repeated spam after warnings.")
    admin = create_user(username: "admin", role: "admin")
    peer = create_user(username: "peer", role: "admin")

    sign_in(admin)
    post admin_user_apply_template_path(peer), params: { template_id: template.id }

    refute peer.reload.is_banned, "a macro must still refuse a peer"
    assert_equal 0, template.reload.uses_count
  end

  test "a macro cannot be applied to the owner account by another operator" do
    template = create_template
    owner = create_user(username: "king", role: "owner")
    admin = create_user(username: "admin", role: "admin")

    sign_in(admin)
    post admin_user_apply_template_path(owner), params: { template_id: template.id }

    assert_redirected_to admin_user_path(owner)
    assert_equal 0, owner.user_warnings.count
  end

  test "a macro cannot be applied to the operator's own account" do
    template = create_template
    owner = create_user(username: "king", role: "owner")

    sign_in(owner)
    post admin_user_apply_template_path(owner), params: { template_id: template.id }

    assert_equal 0, owner.user_warnings.count
  end

  test "the account record only offers macros whose action the operator holds" do
    create_template(name: "Warn macro", action_key: "warn", duration: "30d", category: "spam")
    create_template(name: "Ban macro", action_key: "ban", duration: "7d",
                    category: "", reason: "Ban reason.")
    moderator = create_user(username: "mod", role: "moderator")
    target = create_user(username: "member")

    sign_in(moderator)
    get admin_user_path(target)

    assert_response :success
    assert_match(/Warn macro/, response.body)
    assert_no_match(/Ban macro/, response.body)
  end

  test "a ban macro applies a timed ban, never a permanent one" do
    template = create_template(name: "Ban spam", action_key: "ban", duration: "7d",
                               category: "", reason: "Repeated spam after warnings.")
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")

    sign_in(owner)
    post admin_user_apply_template_path(target), params: { template_id: template.id }

    target.reload
    assert target.is_banned
    refute target.ban_permanent, "a macro must never file a permanent ban"
    assert target.ban_expires_at.present?
  end
end
