require "test_helper"

# The moderator wellness controls. Interactive blurring is a safety default the
# operator lifts on purpose, never a permanent block, and the break reminder is
# a prompt rather than a rule. These cover both directions of the blur toggle,
# the break clock, and the permission that gates the screen.
class AdminWellnessTest < ActionDispatch::IntegrationTest
  def media_tweet(author:, path: "media/watched_one_1.png")
    Tweet.create!(user: author, body: "look", media_path: path)
  end

  test "the wellness screen renders for an operator and defaults to blurred" do
    owner = create_user(username: "king", role: "owner")
    sign_in(owner)

    get admin_wellness_path

    assert_response :success
    assert_match(/Moderator wellness/, response.body)
    assert_match(/Media is blurred by default/, response.body)
    assert ModeratorSetting.for(owner).sensitive_media_blurred?
  end

  test "turning blurring off is audited and the reports screen stops hiding media" do
    owner = create_user(username: "king", role: "owner")
    member = create_user(username: "member")
    tweet = media_tweet(author: member)
    Report.create!(user: member, reporter: owner, category: "other", detail: "reported", state: "open", tweet: tweet)

    sign_in(owner)

    # Blurred first: the reveal cover is on the attachment.
    get admin_reports_path
    assert_match "ops-media ops-media-blurred", response.body
    assert_match "ops-media-reveal", response.body

    post admin_wellness_blur_path, params: { sensitive_media_blurred: "0" }
    assert_redirected_to admin_wellness_path
    refute ModeratorSetting.for(owner).reload.sensitive_media_blurred?
    assert AuditLog.exists?(action: "wellness.media_blur", actor_id: owner.id)

    # Now the same attachment is shown in full, with no cover.
    get admin_reports_path
    assert_response :success
    # The class is gone from the rendered attachment; the layout script still
    # names it, so the assertion is on the element rather than the page text.
    assert_no_match(/class="ops-media ops-media-blurred"/, response.body)
    assert_no_match(/ops-media-reveal/, response.body)
  end

  test "blurring can be turned back on and is recorded both ways" do
    owner = create_user(username: "king", role: "owner")
    sign_in(owner)

    post admin_wellness_blur_path, params: { sensitive_media_blurred: "0" }
    post admin_wellness_blur_path, params: { sensitive_media_blurred: "1" }

    assert ModeratorSetting.for(owner).reload.sensitive_media_blurred?
    assert_equal 2, AuditLog.where(action: "wellness.media_blur", actor_id: owner.id).count
  end

  test "the break reminder fires after an unbroken interval and resets on a break" do
    owner = create_user(username: "king", role: "owner")
    setting = ModeratorSetting.for(owner)
    setting.update!(break_reminder_minutes: 90, shift_started_at: 200.minutes.ago, last_break_at: 200.minutes.ago)

    sign_in(owner)
    get admin_wellness_path

    assert_response :success
    assert_match(/Time for a break/, response.body)

    post admin_wellness_break_path

    assert_redirected_to admin_wellness_path
    refute ModeratorSetting.for(owner).reload.break_due?
    assert AuditLog.exists?(action: "wellness.break", actor_id: owner.id)

    get admin_wellness_path
    assert_no_match(/Time for a break/, response.body)
  end

  test "snoozing pushes the reminder one interval forward" do
    owner = create_user(username: "king", role: "owner")
    setting = ModeratorSetting.for(owner)
    setting.update!(break_reminder_minutes: 90, shift_started_at: 120.minutes.ago, last_break_at: 120.minutes.ago)

    sign_in(owner)
    post admin_wellness_snooze_path

    assert_redirected_to admin_wellness_path
    refute ModeratorSetting.for(owner).reload.break_due?
    assert AuditLog.exists?(action: "wellness.break_snoozed", actor_id: owner.id)
  end

  test "an out-of-range interval falls back to the default" do
    owner = create_user(username: "king", role: "owner")
    sign_in(owner)

    post admin_wellness_interval_path, params: { break_reminder_minutes: "5" }

    assert_redirected_to admin_wellness_path
    assert_equal ModeratorSetting::DEFAULT_BREAK_MINUTES,
                 ModeratorSetting.for(owner).reload.break_reminder_minutes
  end

  test "a moderator without the wellness grant is refused" do
    create_user(username: "king", role: "owner")
    limited = create_user(username: "limited", role: "moderator")
    role = limited.role
    permission = Permission.find_by!(key: "wellness.manage")
    RolePermission.where(role_id: role.id, permission_id: permission.id).delete_all

    sign_in(limited)
    get admin_wellness_path

    assert_redirected_to admin_root_path
    assert_match(/wellness\.manage/, flash[:alert])
  end

  test "wellness state is always the current operator's own row" do
    owner = create_user(username: "king", role: "owner")
    other = create_user(username: "other", role: "owner")
    ModeratorSetting.for(other).update!(sensitive_media_blurred: false)

    sign_in(owner)
    get admin_wellness_path

    assert_response :success
    assert_match(/Media is blurred by default/, response.body)
    assert ModeratorSetting.for(owner).sensitive_media_blurred?
  end
end
