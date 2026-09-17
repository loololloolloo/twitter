require "test_helper"

# A banned account must see the ban screen and nothing else, and an expired
# timed ban must lift itself.
class BanFlowTest < ActionDispatch::IntegrationTest
  test "a banned user is redirected to the ban screen from any page" do
    user = create_user(username: "banned_one")
    user.update!(is_banned: true, ban_reason: "Spamming", ban_permanent: true)

    sign_in(user)
    get home_path

    assert_redirected_to banned_path
    follow_redirect!
    assert_response :success
    assert_match(/Spamming/, response.body)
  end

  test "the ban screen is reachable and explains a timed ban" do
    user = create_user(username: "banned_two")
    # Sit clearly inside the "2 days" window. Landing exactly on a day boundary
    # makes the rendered duration depend on sub-second timing between setup and
    # render, which reads as a flake rather than a real difference.
    user.update!(is_banned: true, ban_reason: "Rude", ban_permanent: false,
                 ban_expires_at: 2.days.from_now + 1.hour)

    sign_in(user)
    get banned_path

    assert_response :success
    assert_match(/Rude/, response.body)
    assert_match(/2 days/, response.body)
  end

  test "signing in while banned lands on the ban screen" do
    user = create_user(username: "banned_three")
    user.update!(is_banned: true, ban_reason: "Abuse", ban_permanent: true)

    sign_in(user)
    assert_redirected_to banned_path
  end

  test "an expired ban clears itself on read" do
    user = create_user(username: "time_served")
    user.update!(is_banned: true, ban_reason: "Cooling off", ban_permanent: false,
                 ban_expires_at: 1.hour.ago)

    refute user.banned?
    refute user.reload.is_banned
    assert_nil user.ban_expires_at
  end

  test "a currently active timed ban is not cleared" do
    user = create_user(username: "still_banned")
    user.update!(is_banned: true, ban_reason: "Cooling off", ban_permanent: false,
                 ban_expires_at: 5.hours.from_now)

    assert user.banned?
    assert user.reload.is_banned
  end

  test "a banned user can still reach the ban screen instead of looping" do
    user = create_user(username: "banned_four")
    user.update!(is_banned: true, ban_reason: "Nope", ban_permanent: true)

    sign_in(user)
    get banned_path
    assert_response :success
  end

  test "an unbanned user is not redirected" do
    user = create_user(username: "fine")

    sign_in(user)
    get home_path
    assert_response :success
  end
end