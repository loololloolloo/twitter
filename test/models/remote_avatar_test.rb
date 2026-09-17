require "test_helper"

# The fetcher is the one place the app makes an outbound request on behalf of a
# user-selected input, so these tests concentrate on what it refuses. Most run
# entirely offline by calling the validation helpers directly; the last group
# performs a real download and skips when the network is not reachable.
class RemoteAvatarTest < ActiveSupport::TestCase
  # ---------------------------------------------------------------- seeds

  test "a seed is reduced to characters that cannot alter the request path" do
    assert_equal "helloworld", RemoteAvatar.safe_seed("hello world")
    assert_equal "etcpasswd", RemoteAvatar.safe_seed("../../etc/passwd")
    assert_equal "abcde", RemoteAvatar.safe_seed("a?b#c/d\\e")
    assert_empty RemoteAvatar.safe_seed("///")
    assert_empty RemoteAvatar.safe_seed(nil)
  end

  test "a seed cannot carry its own query string or host" do
    seed = RemoteAvatar.safe_seed("x&size=9999&host=evil.test")
    assert_equal "xsize9999hosteviltest", seed
    url = RemoteAvatar::PROVIDERS["dicebear"][:build].call(seed, "avataaars")
    assert_equal "api.dicebear.com", URI.parse(url).host
    refute_includes url, "evil.test"
  end

  test "an overlong seed is truncated" do
    assert_equal 64, RemoteAvatar.safe_seed("a" * 500).length
  end

  # ---------------------------------------------------------------- sniffing

  test "image types are identified by their leading bytes" do
    assert_equal "png", RemoteAvatar.sniff_type("\x89PNG\r\n\x1a\n".b + "rest")
    assert_equal "jpeg", RemoteAvatar.sniff_type("\xFF\xD8\xFF".b + "rest")
    assert_equal "gif", RemoteAvatar.sniff_type("GIF89a" + "rest")
    assert_equal "webp", RemoteAvatar.sniff_type("RIFFxxxxWEBP" + "rest")
  end

  test "a non-image response is not identified as an image" do
    assert_nil RemoteAvatar.sniff_type("<html><body>hi</body></html>")
    assert_nil RemoteAvatar.sniff_type("")
    # An SVG is a document that can execute script; it must not be accepted.
    assert_nil RemoteAvatar.sniff_type("<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>")
  end

  # ------------------------------------------------------- address guarding

  test "private, loopback and link-local addresses are refused" do
    %w[
      127.0.0.1 127.1.2.3 10.0.0.1 10.255.255.255 192.168.1.1 192.168.0.1
      172.16.0.1 172.31.255.255 169.254.169.254 100.64.0.1 0.0.0.0
      ::1 fd00::1 fe80::1 ::
    ].each do |address|
      assert_not RemoteAvatar.public_address?(address), "#{address} should be refused"
    end
  end

  test "public addresses are allowed" do
    %w[8.8.8.8 1.1.1.1 93.184.216.34 2606:4700:4700::1111].each do |address|
      assert RemoteAvatar.public_address?(address), "#{address} should be allowed"
    end
  end

  test "a host outside the allowlist is refused" do
    assert_nil RemoteAvatar.normalize(URI.parse("https://evil.test/x.png"), %w[api.dicebear.com])
    assert_nil RemoteAvatar.normalize(URI.parse("https://i.pinimg.com/x.png"), %w[api.dicebear.com])
  end

  test "plain http is refused even for an allowed host" do
    assert_nil RemoteAvatar.normalize(URI.parse("http://api.dicebear.com/x.png"), %w[api.dicebear.com])
  end

  test "an allowed host that resolves inward is still refused" do
    # The name is permitted, but the address behind it is not, which is the
    # whole point of resolving before the request.
    assert_nil RemoteAvatar.normalize(URI.parse("https://169.254.169.254/latest/meta-data"),
                                      %w[169.254.169.254])
    assert_nil RemoteAvatar.normalize(URI.parse("https://127.0.0.1/x"), %w[127.0.0.1])
  end

  # ------------------------------------------------------------ fetch entry

  test "an unknown provider yields nothing" do
    assert_nil RemoteAvatar.fetch(seed: "abc", provider: "pinterest")
    assert_nil RemoteAvatar.fetch(seed: "abc", provider: "not-a-provider")
  end

  test "an empty seed yields nothing" do
    assert_nil RemoteAvatar.fetch(seed: "", provider: "dicebear")
    assert_nil RemoteAvatar.fetch(seed: "///", provider: "dicebear")
  end

  test "an unknown style falls back to the provider's first style" do
    # A style outside the provider's list is replaced rather than interpolated
    # blindly, so a hostile style string cannot reach the URL.
    url = RemoteAvatar::PROVIDERS["dicebear"][:build].call("abc", "avataaars")
    assert_includes url, "/avataaars/"
    assert_not_includes url, ".."

    skip "network unavailable" unless network_available?
    path = RemoteAvatar.fetch(seed: "style-fallback", provider: "dicebear", style: "../../etc/passwd")
    assert_not_nil path, "an unknown style should fall back, not fail"
  ensure
    if defined?(path) && path
      full = Uploads::ROOT.join(path)
      File.delete(full) if File.exist?(full)
    end
  end

  # ---------------------------------------------------------- real download

  # These make a genuine request. They are the only tests here that need the
  # network, so they are skipped when the provider cannot be reached rather than
  # failing the suite on an offline machine.
  def network_available?
    @network_available ||= begin
      require "resolv"
      !RemoteAvatar.resolve("api.dicebear.com").empty?
    rescue StandardError
      false
    end
  end

  test "a real download produces a stored image file" do
    skip "network unavailable" unless network_available?

    path = RemoteAvatar.fetch(seed: "test-seed-real", provider: "dicebear")

    assert_not_nil path, "expected dicebear to return a picture"
    assert path.start_with?("avatars/"), "path should be relative to /uploads"

    full = Uploads::ROOT.join(path)
    assert File.exist?(full), "expected #{full} to exist"
    assert File.size(full).positive?

    # The stored file really is a PNG, matching the sniffed extension.
    bytes = File.binread(full, 8)
    assert_equal "\x89PNG\r\n\x1a\n".b, bytes
  ensure
    File.delete(full) if defined?(full) && full && File.exist?(full)
  end

  test "the same seed produces the same picture" do
    skip "network unavailable" unless network_available?

    first = RemoteAvatar.fetch(seed: "stable-seed", provider: "dicebear")
    second = RemoteAvatar.fetch(seed: "stable-seed", provider: "dicebear")

    assert_not_nil first
    assert_not_nil second

    a = Digest::SHA256.hexdigest(File.binread(Uploads::ROOT.join(first)))
    b = Digest::SHA256.hexdigest(File.binread(Uploads::ROOT.join(second)))
    assert_equal a, b, "the same seed should give the same picture"
  ensure
    [ first, second ].each do |p|
      next if p.nil?
      full = Uploads::ROOT.join(p)
      File.delete(full) if File.exist?(full)
    end
  end

  test "a redirect to an undeclared host is not followed" do
    skip "network unavailable" unless network_available?

    # Picsum answers with a redirect to its CDN. With the CDN host declared the
    # download succeeds; with the CDN host withheld it must be refused instead
    # of followed, because following it would bypass the allowlist.
    body, _type = RemoteAvatar.download("https://picsum.photos/seed/x/256/256.jpg",
                                        host: "picsum.photos")
    assert_nil body, "an undeclared redirect host must not be followed"

    body, type = RemoteAvatar.download("https://picsum.photos/seed/x/256/256.jpg",
                                       host: "picsum.photos",
                                       redirect_hosts: %w[fastly.picsum.photos])
    assert_not_nil body
    assert_equal "jpeg", type
  end

  test "a host that is not resolvable yields nothing" do
    assert_nil RemoteAvatar.fetch(seed: "abc", provider: "dicebear") if RemoteAvatar.resolve("api.dicebear.com").empty?

    assert_equal [], RemoteAvatar.resolve("no-such-host.invalid")
  end
end