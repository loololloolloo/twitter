require "test_helper"

# The admin avatar importer. These tests exercise the real controller and the
# real fetcher; the assertions that need a provider are skipped when the network
# is unreachable, everything else runs offline.
class AdminAvatarsTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user(username: "owner_av", role: "owner")
    @moderator = create_user(username: "mod_av", role: "moderator")
    @bot = create_user(username: "pictureless_bot", is_bot: true)
    @bot.update_columns(avatar_path: nil)
  end

  def network_available?
    !RemoteAvatar.resolve("api.dicebear.com").empty?
  rescue StandardError
    false
  end

  test "an owner can open the avatars screen" do
    sign_in(@owner)
    get admin_avatars_path

    assert_response :success
    assert_match(/Profile pictures/, response.body)
  end

  test "a moderator without users.avatar is turned away" do
    sign_in(@moderator)
    get admin_avatars_path

    # AdminController redirects with an alert rather than rendering.
    assert_response :redirect
    follow_redirect!
    assert_match(/users\.avatar/, response.body)
  end

  test "a moderator cannot reach the per-user import page" do
    sign_in(@moderator)
    get admin_user_avatars_path(@bot)

    assert_response :redirect
    follow_redirect!
    assert_match(/users\.avatar/, response.body)
  end

  test "the avatars screen counts accounts without a picture" do
    sign_in(@owner)
    get admin_avatars_path

    assert_response :success
    assert_equal 1, User.bots.where(avatar_path: [ nil, "" ]).count
    assert_match(/1/, response.body)
  end

  test "an owner can fetch and assign a picture for one account" do
    skip "network unavailable" unless network_available?

    sign_in(@owner)
    post admin_user_avatar_apply_path(@bot), params: { provider: "dicebear" }

    assert_response :redirect
    @bot.reload
    assert @bot.avatar_path.present?, "expected the bot to gain an avatar"

    full = Uploads::ROOT.join(@bot.avatar_path)
    assert File.exist?(full), "expected the stored file to exist"

    # The assignment is audited.
    assert AuditLog.where(action: "users.avatar", target: "user:#{@bot.id}").exists?
  ensure
    if @bot&.avatar_path.present?
      full = Uploads::ROOT.join(@bot.avatar_path)
      File.delete(full) if File.exist?(full)
    end
  end

  test "an unknown provider falls back rather than reaching an arbitrary host" do
    skip "network unavailable" unless network_available?

    sign_in(@owner)
    post admin_user_avatar_apply_path(@bot), params: { provider: "https://evil.test/steal" }

    assert_response :redirect
    follow_redirect!
    # The fallback is dicebear, so the account gains a legitimate picture and
    # nothing is fetched from the supplied host.
    @bot.reload
    assert @bot.avatar_path.present?
    assert_includes @bot.avatar_path, "dicebear"
  ensure
    if @bot&.avatar_path.present?
      full = Uploads::ROOT.join(@bot.avatar_path)
      File.delete(full) if File.exist?(full)
    end
  end

  test "a bulk import fills in accounts that have no picture" do
    skip "network unavailable" unless network_available?

    second = create_user(username: "pictureless_two", is_bot: true)
    second.update_columns(avatar_path: nil)

    sign_in(@owner)
    post admin_avatars_path, params: { provider: "dicebear", scope: "missing" }

    assert_response :redirect
    assert @bot.reload.avatar_path.present?
    assert second.reload.avatar_path.present?
    assert_equal 0, User.bots.where(avatar_path: [ nil, "" ]).count
  ensure
    [ @bot, second ].compact.each do |bot|
      next if bot.avatar_path.blank?
      full = Uploads::ROOT.join(bot.avatar_path)
      File.delete(full) if File.exist?(full)
    end
  end

  # ------------------------------------------------------- replacing a file

  test "replacing a picture removes the file it replaced" do
    # Give the account a picture that stands in for a previous import, then
    # replace it and check the old file is gone rather than orphaned.
    old_dir = Uploads::ROOT.join("avatars")
    FileUtils.mkdir_p(old_dir)
    old_name = "remote_test_orphancheck.png"
    old_path = "avatars/#{old_name}"
    File.binwrite(old_dir.join(old_name), "\x89PNG\r\n\x1a\n".b + "old")
    @bot.update_columns(avatar_path: old_path)

    skip "network unavailable" unless network_available?

    sign_in(@owner)
    post admin_user_avatar_apply_path(@bot), params: { provider: "dicebear" }

    assert_response :redirect
    @bot.reload
    assert_not_equal old_path, @bot.avatar_path
    assert_not File.exist?(old_dir.join(old_name)), "the replaced file should have been removed"
  ensure
    File.delete(old_dir.join(old_name)) if defined?(old_dir) && File.exist?(old_dir.join(old_name))
    if @bot&.avatar_path.present?
      full = Uploads::ROOT.join(@bot.avatar_path)
      File.delete(full) if File.exist?(full)
    end
  end

  # ---------------------------------------------------- removal path safety

  test "removing an upload refuses to leave the uploads directory" do
    outside = Rails.root.join("tmp", "outside_upload_target.txt")
    FileUtils.mkdir_p(outside.dirname)
    File.write(outside, "must not be deleted")

    # This path resolves to the file above; without the guard it would be
    # deleted, so the assertion below is what proves the guard works.
    escape = outside.relative_path_from(Uploads::ROOT).to_s
    assert escape.start_with?(".."), "the escape path should climb out of the uploads root"
    assert_equal outside.to_s, Uploads::ROOT.join(escape).cleanpath.to_s,
                 "the escape path must really point at the file under test"

    Uploads.remove(escape)
    assert File.exist?(outside), "a path outside uploads must not be removed"

    # An absolute path is not silently accepted either.
    Uploads.remove("/etc/hostname")
    assert File.exist?("/etc/hostname")

    Uploads.remove(nil)
    Uploads.remove("")

    File.delete(outside)
  end

  test "removing an upload deletes a file inside the uploads directory" do
    dir = Uploads::ROOT.join("avatars")
    FileUtils.mkdir_p(dir)
    name = "remote_test_removal.png"
    File.binwrite(dir.join(name), "x")

    Uploads.remove("avatars/#{name}")
    assert_not File.exist?(dir.join(name))
  end
end