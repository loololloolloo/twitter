# Imports profile pictures from external providers.
#
# The site has no licensed photo set and no image library, so a picture has to
# be either drawn locally (see AvatarGenerator) or fetched from somewhere that
# offers one under terms that permit it. This module does the second thing,
# restricted to providers that generate or licence their images:
#
#   dicebear   illustrated avatars, several styles, CC0/free for any use
#   robohash   robot/monster avatars, free for any use
#   picsum     photographs from Unsplash, served for free use
#
# Why a provider registry rather than a free-form URL field: a request that
# takes a URL from a user and fetches it server-side is a server-side request
# forgery hole. It can be pointed at the app's own loopback, at cloud metadata
# endpoints (169.254.169.254), or at any host on the internal network, and the
# response is then written to disk or rendered back. Even restricted to three
# hosts, a naked fetch is not safe, so the checks below are load-bearing and
# every one of them is enforced on the *resolved address*, not just the URL.
#
# The flow is: build a URL from the registry, validate the resolved IP, fetch
# with a small timeout and a hard size cap, check the first bytes really are an
# image, then write it under public/uploads/avatars.
module RemoteAvatar
  require "net/http"
  require "resolv"
  require "ipaddr"
  require "securerandom"
  require "fileutils"

  # Hard ceiling on a downloaded picture. Providers serve avatars well under
  # this; the cap exists so a hostile response cannot fill the disk.
  MAX_BYTES = 2 * 1024 * 1024

  # How long to wait for the connection and for the whole read.
  OPEN_TIMEOUT = 4
  READ_TIMEOUT = 8

  # How many redirect hops to follow. Kept at one so a redirect chain cannot
  # walk the request somewhere the allowlist would not otherwise permit.
  MAX_REDIRECTS = 1

  # Image types accepted, mapped to what the sniffer in `sniff_type` returns.
  # SVG is deliberately absent: an SVG is a document that can carry script, and
  # these files are served back to browsers from the app's own origin.
  ALLOWED_TYPES = {
    "png" => ".png",
    "jpeg" => ".jpg",
    "gif" => ".gif",
    "webp" => ".webp"
  }.freeze

  # Hosts this module is willing to contact, with the URL builder for each.
  # `seed` is interpolated into the path, so it must be restricted to a safe
  # character set before it gets here (see `safe_seed`).
  PROVIDERS = {
    "dicebear" => {
      label: "DiceBear (illustrated)",
      host: "api.dicebear.com",
      redirect_hosts: [],
      build: ->(seed, style) {
        "https://api.dicebear.com/9.x/#{style}/png?seed=#{seed}&size=256"
      },
      styles: %w[avataaars bottts fun-emoji pixel-art thumbs lorelei notionists]
    },
    "robohash" => {
      label: "Robohash (robots and monsters)",
      host: "robohash.org",
      redirect_hosts: [],
      build: ->(seed, _style) { "https://robohash.org/#{seed}.png?size=256x256" },
      styles: %w[robot monster robot-head]
    },
    "picsum" => {
      label: "Lorem Picsum (photographs)",
      host: "picsum.photos",
      # Picsum serves the bytes from a CDN after a redirect, so that one extra
      # host is declared here and still goes through the address checks.
      redirect_hosts: %w[fastly.picsum.photos],
      build: ->(seed, _style) { "https://picsum.photos/seed/#{seed}/256/256.jpg" },
      styles: %w[photo]
    }
  }.freeze

  # Fetches a picture for `seed` and stores it, returning the path relative to
  # /uploads (the form `avatar_path` expects), or nil when nothing usable came
  # back. Failure is quiet because this runs in bulk: one dead request should
  # not stop a sweep over hundreds of accounts.
  def self.fetch(seed:, provider: "dicebear", style: nil, root: Uploads::ROOT)
    entry = PROVIDERS[provider.to_s]
    return nil if entry.nil?

    safe = safe_seed(seed)
    return nil if safe.blank?

    style = entry[:styles].first unless entry[:styles].include?(style.to_s)
    url = entry[:build].call(safe, style)

    body, type = download(url, host: entry[:host], redirect_hosts: entry[:redirect_hosts])
    return nil if body.nil?

    ext = ALLOWED_TYPES[type]
    return nil if ext.nil?

    write(body, ext, provider: provider, root: root)
  end

  # A seed is interpolated into a request path, so it is reduced to characters
  # that cannot alter the URL's host or path: letters, digits and dashes only.
  # This is what keeps a crafted seed from escaping the provider's path.
  def self.safe_seed(seed)
    seed.to_s.gsub(/[^A-Za-z0-9-]/, "").first(64)
  end

  # Performs the request and returns [body, type], or [nil, nil] on any refusal
  # or failure. Every reason for refusing is a hard return, never a warning.
  #
  # `host` is the provider's own host. `redirect_hosts` are the extra hosts that
  # provider is known to redirect to; a redirect anywhere else is refused rather
  # than followed, because following it would contact a host that never went
  # through the checks below.
  def self.download(url, host:, redirect_hosts: [])
    uri = URI.parse(url)
    target = normalize(uri, [ host ] + Array(redirect_hosts))
    return [ nil, nil ] if target.nil?

    body = nil
    MAX_REDIRECTS.downto(0) do |_hop|
      body = http_get(target)
      break unless body.is_a?(String) && body.start_with?("REDIRECT:")

      followed = normalize(URI.parse(body.delete_prefix("REDIRECT:")), [ host ] + Array(redirect_hosts))
      return [ nil, nil ] if followed.nil?

      target = followed
    end

    return [ nil, nil ] unless body.is_a?(String)
    # Ran out of hops while still being redirected.
    return [ nil, nil ] if body.start_with?("REDIRECT:")

    [ body, sniff_type(body) ]
  rescue URI::InvalidURIError, SocketError, Timeout::Error, IOError, SystemCallError
    [ nil, nil ]
  end

  # Checks a parsed URL against the allowlist and returns it with its validated
  # address attached, or nil when it should not be contacted.
  #
  # Resolving before the request is what makes this an allowlist and not just a
  # name check: a permitted hostname whose DNS answer points at the loopback or
  # at a metadata address is refused here.
  def self.normalize(uri, allowed_hosts)
    return nil unless uri.is_a?(URI::HTTPS)
    return nil unless allowed_hosts.include?(uri.host)

    addresses = resolve(uri.host)
    return nil if addresses.empty?
    return nil unless addresses.all? { |ip| public_address?(ip) }

    [ uri, addresses.first ]
  end

  # Opens the connection to a specific validated address rather than letting
  # Net::HTTP resolve the name again, which would reopen the gap between the
  # check and the use.
  def self.http_get(target)
    uri, address = target
    http = Net::HTTP.new(uri.host, uri.port)
    http.ipaddr = address
    http.use_ssl = true
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT

    request = Net::HTTP::Get.new(uri.request_uri)
    request["User-Agent"] = "twitter-avatar-import"

    body = nil
    http.start do |session|
      session.request(request) do |response|
        # A redirect is reported back to `download`, which re-runs the
        # allowlist and address checks on the target before anyone follows it.
        return "REDIRECT:#{URI.join(uri, response['location'])}" if response.is_a?(Net::HTTPRedirection) && response["location"]

        return nil unless response.is_a?(Net::HTTPSuccess)

        body = +""
        response.read_body do |chunk|
          body << chunk
          # Stop as soon as the cap is passed instead of trusting a header.
          raise IOError, "avatar exceeded #{MAX_BYTES} bytes" if body.bytesize > MAX_BYTES
        end
      end
    end
    body
  end

  # Resolves a hostname to its addresses.
  def self.resolve(host)
    Resolv.getaddresses(host).reject(&:blank?)
  rescue Resolv::ResolvError
    []
  end

  # True for a globally routable address. Anything private, loopback, link-local
  # (which includes the cloud metadata address 169.254.169.254), multicast or
  # otherwise reserved is refused.
  def self.public_address?(address)
    ip = IPAddr.new(address)
    return false if ip.loopback?
    return false if ip.private?
    return false if ip.link_local?
    return false if ip.to_s.start_with?("169.254.")  # link-local, incl. cloud metadata
    return false if ip.to_s.start_with?("100.64.")   # carrier-grade NAT
    # Unspecified (0.0.0.0 and ::) and the "this network" block are not real
    # destinations; IPAddr does not class either as private.
    return false if ip.to_s.start_with?("0.")
    return false if ip.to_s == "::"

    # IPv6 unique-local and site-local ranges.
    return false if ip.ipv6? && (ip.to_s.start_with?("fc", "fd", "fe80"))

    true
  rescue IPAddr::InvalidAddressError
    false
  end

  # Identifies an image from its leading bytes, so the stored file's extension
  # reflects what it actually is rather than what the server claimed. This is
  # the check that stops an HTML or script response being saved with a .png
  # name and then served from the app's origin.
  def self.sniff_type(body)
    bytes = body.to_s.b
    return "png" if bytes.start_with?("\x89PNG\r\n\x1a\n".b)
    return "jpeg" if bytes.start_with?("\xFF\xD8\xFF".b)
    return "gif" if bytes.start_with?("GIF87a", "GIF89a")
    return "webp" if bytes.start_with?("RIFF") && bytes[8, 4] == "WEBP"

    nil
  end

  # Writes the picture under the avatars directory and returns its relative
  # path. The name is generated here, so nothing from the remote response can
  # influence where the file lands.
  def self.write(body, ext, provider:, root:)
    dir = root.join("avatars")
    FileUtils.mkdir_p(dir)

    name = "remote_#{provider}_#{SecureRandom.hex(8)}#{ext}"
    File.binwrite(dir.join(name), body)
    "avatars/#{name}"
  end
end