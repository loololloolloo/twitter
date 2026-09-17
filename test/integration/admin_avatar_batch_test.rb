require "test_helper"

# The batch endpoint the "fill in every account" buttons drive. It is called
# once per slice of the population, so the contract that matters is that it
# advances by id, reports when the pass is finished, and stays inside the
# caller's session and permissions.
class AdminAvatarBatchTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user(username: "owner_batch", role: "owner")
    @moderator = create_user(username: "mod_batch", role: "moderator")

    @bots = 3.times.map do |i|
      bot = create_user(username: "batch_bot_#{i}", is_bot: true)
      bot.update_columns(avatar_path: nil)
      bot
    end
  end

  def network_available?
    !RemoteAvatar.resolve("api.dicebear.com").empty?
  rescue StandardError
    false
  end

  def cleanup
    @bots.each do |bot|
      next if bot.reload.avatar_path.blank?
      full = Uploads::ROOT.join(bot.avatar_path)
      File.delete(full) if File.exist?(full)
    end
  end

  test "a moderator without users.avatar cannot drive the batch" do
    sign_in(@moderator)
    post admin_avatars_batch_path, params: { provider: "dicebear", after_id: 0 }

    assert_response :redirect
    assert_nil @bots.first.reload.avatar_path
  end

  test "an unknown provider is refused rather than fetched" do
    skip "network unavailable" unless network_available?

    sign_in(@owner)
    post admin_avatars_batch_path,
         params: { provider: "https://evil.test/steal", after_id: 0, scope: "missing" }

    assert_response :success
    # An unrecognized value falls back to dicebear; nothing is fetched from the
    # supplied host.
    assert_includes @bots.first.reload.avatar_path.to_s, "dicebear"
  ensure
    cleanup
  end

  test "a batch fills in accounts and reports that the pass is finished" do
    skip "network unavailable" unless network_available?

    sign_in(@owner)
    post admin_avatars_batch_path, params: { provider: "dicebear", after_id: 0, scope: "missing" }

    assert_response :success
    body = JSON.parse(response.body)

    assert_equal 3, body["processed"]
    assert_equal 3, body["applied"]
    assert_equal 0, body["failed"]
    assert body["done"], "a short batch means the pass is over"
    assert_equal 0, body["remaining"]
    assert @bots.all? { |b| b.reload.avatar_path.present? }
  ensure
    cleanup
  end

  test "a batch after the last id processes nothing and reports done" do
    skip "network unavailable" unless network_available?

    sign_in(@owner)
    post admin_avatars_batch_path,
         params: { provider: "dicebear", after_id: @bots.last.id, scope: "missing" }

    assert_response :success
    body = JSON.parse(response.body)

    assert_equal 0, body["processed"]
    assert body["done"], "an empty batch must terminate the run rather than loop"
  end

  test "walking by id covers every account without repeating one" do
    skip "network unavailable" unless network_available?

    sign_in(@owner)

    seen = []
    after_id = 0
    loops = 0

    loop do
      post admin_avatars_batch_path,
           params: { provider: "dicebear", after_id: after_id, scope: "missing" }
      body = JSON.parse(response.body)

      seen << body["processed"]
      after_id = body["last_id"]
      loops += 1
      break if body["done"] || loops > 10
    end

    assert_operator loops, :<=, 10, "the pass should terminate"
    assert_equal 3, seen.sum, "each account should be examined exactly once"
    assert @bots.all? { |b| b.reload.avatar_path.present? }
  ensure
    cleanup
  end

  test "a random pass assigns a valid provider rather than an arbitrary host" do
    skip "network unavailable" unless network_available?

    sign_in(@owner)
    post admin_avatars_batch_path,
         params: { provider: "random", after_id: 0, scope: "missing", salt: "test-salt" }

    assert_response :success
    body = JSON.parse(response.body)

    assert_equal 3, body["applied"]
    @bots.each do |bot|
      path = bot.reload.avatar_path
      assert path.present?, "expected a picture"
      assert path.start_with?("avatars/remote_"), "unexpected path #{path.inspect}"
    end
  ensure
    cleanup
  end

  test "the same seed returns the same picture, so a run is reproducible" do
    skip "network unavailable" unless network_available?

    # Filenames carry a random suffix, so a repeated import writes a new file.
    # What makes a run reproducible is that the same seed returns the same
    # bytes, which is the property the salt is built on.
    first = RemoteAvatar.fetch(seed: "repro-seed", provider: "robohash")
    second = RemoteAvatar.fetch(seed: "repro-seed", provider: "robohash")

    assert first.present? && second.present?, "both fetches should succeed"
    assert_equal File.binread(Uploads::ROOT.join(first)),
                 File.binread(Uploads::ROOT.join(second)),
                 "the same seed must return the same image"
  ensure
    [ first, second ].compact.each do |path|
      full = Uploads::ROOT.join(path)
      File.delete(full) if File.exist?(full)
    end
  end
end
