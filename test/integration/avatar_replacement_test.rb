require "test_helper"

# Uploading a new avatar or banner replaces the file the row used to point at.
# Nothing else tracks that file, so it has to be removed when it is replaced,
# and a file written before a failed save must not be left behind either.
class AvatarReplacementTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(username: "uploader", role: "user")
    @user.update_columns(avatar_path: nil, banner_path: nil)
    @dir = Uploads::ROOT.join("avatars")
    FileUtils.mkdir_p(@dir)
    # Uploads.store renames to "<id>_<hex>.<ext>", so a before/after snapshot is
    # the only reliable way to prove nothing was left behind.
    @before = Dir.glob(@dir.join("#{@user.id}_*")).map { |f| File.basename(f) }
  end

  teardown do
    (Dir.glob(@dir.join("#{@user.id}_*")).map { |f| File.basename(f) } - @before).each do |name|
      File.delete(@dir.join(name))
    end
  end

  def wrote_new_files
    Dir.glob(@dir.join("#{@user.id}_*")).map { |f| File.basename(f) } - @before
  end

  def upload_file(name, bytes = "\x89PNG\r\n\x1a\n".b + name)
    path = Rails.root.join("tmp", name)
    FileUtils.mkdir_p(path.dirname)
    File.binwrite(path, bytes)
    Rack::Test::UploadedFile.new(path, "image/png")
  end

  test "uploading a new avatar removes the file it replaced" do
    old_name = "#{@user.id}_upload_test_previous.png"
    old_path = "avatars/#{old_name}"
    File.binwrite(@dir.join(old_name), "old picture")
    @user.update_columns(avatar_path: old_path)
    @before << old_name

    sign_in(@user)
    post settings_path, params: { avatar: upload_file("upload_test_new.png", "new picture") }

    assert_response :redirect
    replaced = @user.reload.avatar_path

    assert replaced.present?, "the account should have gained a picture"
    assert_not_equal old_path, replaced
    assert_not File.exist?(@dir.join(old_name)), "the replaced file should have been removed"
    assert_equal 1, wrote_new_files.size, "exactly the new picture should remain"
  end

  test "a picture is kept when the form is saved without a new upload" do
    kept = "#{@user.id}_upload_test_kept.png"
    File.binwrite(@dir.join(kept), "kept picture")
    @user.update_columns(avatar_path: "avatars/#{kept}")
    @before << kept

    sign_in(@user)
    post settings_path, params: { display_name: "Uploader" }

    assert_response :redirect
    assert_equal "avatars/#{kept}", @user.reload.avatar_path
    assert File.exist?(@dir.join(kept)), "omitting the file must not remove the existing picture"
    assert_empty wrote_new_files, "saving without an upload must not write a file"
  end

  test "a rejected update does not leave the newly written file behind" do
    # The form truncates its fields before assigning them, so the update fails
    # on data already in the row rather than the submitted values. A handle that
    # predates the current format (the kind this app had to repair) is the
    # realistic case: saving settings fails while the upload has already landed.
    @user.update_columns(username: "legacy.broken")

    sign_in(@user)
    post settings_path, params: { avatar: upload_file("upload_test_rejected.png") }

    assert_response :unprocessable_entity
    assert_nil @user.reload.avatar_path, "the failed update must not assign the picture"
    assert_empty wrote_new_files, "a file written for a failed save must be cleaned up"
  end
end
