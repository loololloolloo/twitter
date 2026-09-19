require "test_helper"

# Covers internal staff notes on the admin user page. A note is private context
# for the next operator: it is attributed, dated and append-only, it never
# reaches the member, and it changes nothing about the account. These tests
# check the write path, the guards, the pin ordering, and that the member is
# never notified.
class AdminStaffNotesTest < ActionDispatch::IntegrationTest
  test "an operator with users.notes adds an attributed, dated note" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")

    sign_in(owner)
    post admin_user_note_path(target), params: { body: "Warned about link spam in DMs" }

    assert_redirected_to admin_user_path(target)
    note = target.staff_notes.last
    assert_equal "Warned about link spam in DMs", note.body
    assert_equal owner.id, note.author_id
    refute note.pinned
    assert note.created_at.present?
  end

  test "adding a note records an audit entry carrying the text" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")

    sign_in(owner)
    post admin_user_note_path(target), params: { body: "Escalated to legal" }

    entry = AuditLog.where(action: "users.notes").last
    assert entry, "the note should be audited"
    assert_equal "user:#{target.id}", entry.target
    assert_match(/added note/, entry.detail)
    assert_match(/Escalated to legal/, entry.detail)
  end

  test "an empty note is refused and nothing is stored" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")

    sign_in(owner)
    post admin_user_note_path(target), params: { body: "   " }

    assert_redirected_to admin_user_path(target)
    assert_equal 0, target.staff_notes.count
  end

  test "an over-long note is refused" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")

    sign_in(owner)
    post admin_user_note_path(target), params: { body: "x" * (StaffNote::MAX_BODY + 1) }

    assert_redirected_to admin_user_path(target)
    assert_equal 0, target.staff_notes.count
  end

  test "a pinned note is stored pinned" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")

    sign_in(owner)
    post admin_user_note_path(target), params: { body: "VIP account", pinned: "1" }

    assert target.staff_notes.last.pinned
  end

  test "an operator cannot leave a note on their own account" do
    owner = create_user(username: "king", role: "owner")

    sign_in(owner)
    post admin_user_note_path(owner), params: { body: "Note to self" }

    assert_redirected_to admin_user_path(owner)
    assert_equal 0, owner.staff_notes.count
  end

  test "the owner account cannot be noted by another admin" do
    owner = create_user(username: "king", role: "owner")
    admin = create_user(username: "boss", role: "admin")

    sign_in(admin)
    post admin_user_note_path(owner), params: { body: "Not allowed" }

    assert_equal 0, owner.staff_notes.count
  end

  test "a role without users.notes cannot add a note" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")

    # The owner holds every key, so strip users.notes from the moderator grant
    # and confirm the request is turned away.
    mod_role = Role.find_by!(name: "moderator")
    mod_role.role_permissions.joins(:permission)
            .where(permissions: { key: "users.notes" }).delete_all
    moderator = create_user(username: "mod", role: "moderator")

    sign_in(moderator)
    post admin_user_note_path(target), params: { body: "Nope" }

    assert_equal 0, target.staff_notes.count
  end

  test "a role without users.notes cannot read notes on the record" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")
    StaffNote.create!(user: target, author: owner, body: "Privileged context")

    mod_role = Role.find_by!(name: "moderator")
    mod_role.role_permissions.joins(:permission)
            .where(permissions: { key: "users.notes" }).delete_all
    moderator = create_user(username: "mod", role: "moderator")

    sign_in(moderator)
    get admin_user_path(target)

    assert_response :success
    assert_no_match(/Privileged context/, response.body)
    assert_match(/cannot read or keep internal notes/, response.body)
  end

  test "a moderator holds users.notes and can add one" do
    target = create_user(username: "member")

    assert Role.find_by!(name: "moderator").permissions.exists?(key: "users.notes")

    moderator = create_user(username: "mod", role: "moderator")
    sign_in(moderator)
    post admin_user_note_path(target), params: { body: "Watching this account" }

    assert_equal 1, target.staff_notes.count
  end

  test "a note never notifies the member" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")

    sign_in(owner)
    post admin_user_note_path(target), params: { body: "Internal only" }

    assert_equal 0, target.notifications.count
  end

  test "the user page renders the notes with author and body" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")
    StaffNote.create!(user: target, author: owner, body: "Known ban evader")

    sign_in(owner)
    get admin_user_path(target)

    assert_response :success
    assert_match(/Internal notes/, response.body)
    assert_match(/note-list/, response.body)
    assert_match(/Known ban evader/, response.body)
    assert_match(/@king/, response.body)
  end

  test "an account with no notes says so" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")

    sign_in(owner)
    get admin_user_path(target)

    assert_match(/No internal notes on this account/, response.body)
  end

  test "pinned notes lead the list regardless of age" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")
    StaffNote.create!(user: target, author: owner, body: "Pinned context",
                      pinned: true, created_at: 5.days.ago)
    StaffNote.create!(user: target, author: owner, body: "Recent aside",
                      created_at: 1.hour.ago)

    sign_in(owner)
    get admin_user_path(target)

    body = response.body
    pinned = body.index("Pinned context")
    recent = body.index("Recent aside")
    assert pinned.present? && recent.present?
    assert pinned < recent, "the pinned note should render above the newer one"
  end

  test "pinning toggles and is audited" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")
    note = StaffNote.create!(user: target, author: owner, body: "Context")

    sign_in(owner)
    post admin_user_note_pin_path(target, note)

    assert_redirected_to admin_user_path(target)
    assert note.reload.pinned
    assert AuditLog.where(action: "users.notes").last.detail.include?("pinned note ##{note.id}")

    post admin_user_note_pin_path(target, note)
    refute note.reload.pinned
  end

  test "deleting a note removes the row and keeps its text in the audit trail" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")
    note = StaffNote.create!(user: target, author: owner, body: "Sensitive observation")

    sign_in(owner)
    delete admin_user_note_destroy_path(target, note)

    assert_redirected_to admin_user_path(target)
    refute StaffNote.exists?(note.id)
    entry = AuditLog.where(action: "users.notes").last
    assert_match(/deleted note ##{note.id}/, entry.detail)
    assert_match(/Sensitive observation/, entry.detail)
  end

  test "a note cannot be pinned through another account's path" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")
    other = create_user(username: "other")
    note = StaffNote.create!(user: other, author: owner, body: "Belongs to other")

    sign_in(owner)
    post admin_user_note_pin_path(target, note)

    assert_redirected_to admin_user_path(target)
    refute note.reload.pinned
  end

  test "notes are removed when the account is deleted" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")
    StaffNote.create!(user: target, author: owner, body: "Gone with the account")

    sign_in(owner)
    delete admin_user_destroy_path(target)

    assert_equal 0, StaffNote.where(user_id: target.id).count
  end

  test "the note body is escaped when rendered" do
    owner = create_user(username: "king", role: "owner")
    target = create_user(username: "member")
    StaffNote.create!(user: target, author: owner, body: "<script>alert(1)</script>")

    sign_in(owner)
    get admin_user_path(target)

    assert_no_match(%r{<script>alert\(1\)</script>}, response.body)
    assert_match(/&lt;script&gt;/, response.body)
  end
end