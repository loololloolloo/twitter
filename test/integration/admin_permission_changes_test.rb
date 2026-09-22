require "test_helper"

# Role and permission edits are the change that grants every other capability
# in the panel, so they get their own review surface. These tests check that the
# diff is recorded from the real before/after sets, that a no-op save writes
# nothing, and that a moderator without the grant cannot read the review.
class AdminPermissionChangesTest < ActionDispatch::IntegrationTest
  test "a permission edit records the before/after capability diff" do
    owner = create_user(username: "king", role: "owner")
    sign_in(owner)

    moderator = Role.find_by!(name: "moderator")
    before_keys = moderator.permission_keys

    assert_difference "PermissionChange.count", 1 do
      post admin_permissions_path, params: {
        role_id: moderator.id,
        permissions: before_keys.to_a + %w[users.ban],
        note: "front-line bans"
      }
    end

    change = PermissionChange.recent.first
    assert_equal moderator.id, change.role_id
    assert_equal owner.id, change.actor_id
    assert_includes change.added, "users.ban"
    assert_empty change.removed
    assert_equal "front-line bans", change.note
    assert_includes change.before, "users.view"
    assert_includes change.after, "users.ban"
  end

  test "a removal is recorded as a lost capability" do
    owner = create_user(username: "king", role: "owner")
    sign_in(owner)

    moderator = Role.find_by!(name: "moderator")
    held = moderator.permission_keys

    assert_difference "PermissionChange.count", 1 do
      post admin_permissions_path, params: {
        role_id: moderator.id,
        permissions: (held - [ "users.notes" ]).to_a
      }
    end

    change = PermissionChange.recent.first
    assert_includes change.removed, "users.notes"
    assert_empty change.added
    refute change.after.include?("users.notes")
  end

  test "a save that changes nothing writes no review row" do
    owner = create_user(username: "king", role: "owner")
    sign_in(owner)

    moderator = Role.find_by!(name: "moderator")

    assert_no_difference "PermissionChange.count" do
      post admin_permissions_path, params: {
        role_id: moderator.id, permissions: moderator.permission_keys.to_a
      }
    end
  end

  test "the owner role edit is still refused and records nothing" do
    owner = create_user(username: "king", role: "owner")
    sign_in(owner)

    owner_role = Role.find_by!(name: Role::OWNER)

    assert_no_difference "PermissionChange.count" do
      post admin_permissions_path, params: { role_id: owner_role.id, permissions: [] }
    end

    assert_equal Permission.count, owner_role.reload.permissions.count
  end

  test "the review screen shows the diff and is closed without the grant" do
    owner = create_user(username: "king", role: "owner")
    sign_in(owner)

    moderator = Role.find_by!(name: "moderator")
    post admin_permissions_path, params: {
      role_id: moderator.id,
      permissions: moderator.permission_keys.to_a + %w[users.ban],
      note: "shift cover"
    }

    get admin_permission_changes_path
    assert_response :success
    assert_match(/Permission change review/, response.body)
    assert_match(/users\.ban/, response.body)
    assert_match(/shift cover/, response.body)

    # A moderator reaches the panel but does not hold permissions.review, so
    # the review surface is refused even though they can open other screens.
    delete logout_path
    plain = create_user(username: "mod", role: "moderator")
    sign_in(plain)
    assert_difference -> { PermissionChange.count }, 0 do
      get admin_permission_changes_path
    end
    assert_redirected_to admin_root_path
  end
end
