# Turns a pasted GIF link into a URL that can be embedded directly.
#
# The link people actually copy is usually a *page* (a Tenor or Giphy page),
# not the media file, so accepting only direct links would reject most of what
# gets pasted. This resolves either form, without an API key:
#
#   - a direct media URL on a known host is used as-is;
#   - a Giphy page URL carries the asset id in its slug, so the direct URL is
#     derived from it;
#   - a Tenor page URL does not carry the asset id, so its Open Graph image is
#     read from the page.
#
# Only these hosts are ever contacted, and only over https, because the URL
# comes from a user: an arbitrary host would let a post make the server fetch
# an internal address.
module GifLink
  # Hosts whose media can be embedded. Deliberately small: this is an
  # embed allowlist, not a general-purpose proxy.
  MEDIA_HOSTS = %w[
    media.tenor.com media1.tenor.com c.tenor.com
    media.giphy.com media0.giphy.com media1.giphy.com media2.giphy.com
    media3.giphy.com media4.giphy.com i.giphy.com
  ].freeze

  # Hosts whose pages this will read to find the underlying asset.
  PAGE_HOSTS = %w[tenor.com www.tenor.com giphy.com www.giphy.com].freeze

  DIRECT_EXTENSIONS = %w[.gif .webp].freeze

  MAX_BYTES = 200_000
  OPEN_TIMEOUT = 3
  READ_TIMEOUT = 5

  # Returns an embeddable https URL, or nil when the link cannot be used.
  # `fetcher` is the seam the tests use to supply page HTML without a network
  # call; in production it is the real reader.
  def self.resolve(raw, fetcher: method(:fetch_page))
    url = normalize(raw)
    return nil if url.nil?

    host = url.host.downcase

    return url.to_s if MEDIA_HOSTS.include?(host) && direct_media?(url)
    return giphy_from_page(url) if giphy_page?(host)
    return tenor_from_page(url, fetcher) if PAGE_HOSTS.include?(host)

    nil
  end

  # Accepts what people paste: "tenor.com/..." without a scheme, or "//host/...".
  # Anything that is not http(s) after that is refused, so javascript: and data:
  # URLs never reach a page.
  def self.normalize(raw)
    value = raw.to_s.strip
    return nil if value.empty? || value.length > 2_000

    # A scheme other than http(s) is refused outright rather than being
    # prefixed into something that merely looks like a URL.
    return nil if value.match?(%r{\A[a-z][a-z0-9+.\-]*:}i) && !value.match?(%r{\Ahttps?:}i)

    value = "https:#{value}" if value.start_with?("//")
    value = "https://#{value}" unless value.match?(%r{\Ahttps?://}i)

    url = URI.parse(value)
    return nil unless url.is_a?(URI::HTTPS)
    return nil if url.host.blank?

    url
  rescue URI::InvalidURIError
    nil
  end

  # A direct asset: an image extension on an allowlisted media host. A GIF page
  # served under a media host (Tenor does this) lands here only if it genuinely
  # ends in a GIF or WebP extension, so nothing non-image is embedded.
  def self.direct_media?(url)
    ext = File.extname(url.path.to_s).downcase
    DIRECT_EXTENSIONS.include?(ext) || url.path.to_s.include?("/giphy.")
  end

  def self.giphy_page?(host)
    host == "giphy.com" || host == "www.giphy.com"
  end

  # https://giphy.com/gifs/<slug>-<id> -> https://media.giphy.com/media/<id>/giphy.gif
  # The trailing token of the slug is the asset id.
  def self.giphy_from_page(url)
    segment = url.path.to_s.split("/").reject(&:empty?).last.to_s
    id = segment.split("-").last.to_s
    return nil unless id.match?(/\A[A-Za-z0-9]{5,40}\z/)

    "https://media.giphy.com/media/#{id}/giphy.gif"
  end

  # A Tenor page has no asset id in its URL, so the asset is read from the
  # page's Open Graph metadata instead.
  def self.tenor_from_page(url, fetcher)
    html = fetcher.call(url.to_s)
    return nil if html.blank?

    extract_media_url(html)
  end

  def self.extract_media_url(html)
    candidates = html.scan(/<meta[^>]+(?:property|name)=["']og:(?:image|video)["'][^>]*>/i)
    candidates.each do |tag|
      content = tag[/content=["']([^"']+)["']/i, 1]
      next if content.blank?

      candidate = normalize(html_unescape(content))
      next if candidate.nil?

      host = candidate.host.downcase
      return candidate.to_s if MEDIA_HOSTS.include?(host)
    end

    nil
  end

  # The few entities an og:image attribute is escaped with in practice.
  def self.html_unescape(value)
    value.gsub("&amp;", "&").gsub("&#39;", "'").gsub("&quot;", '"')
  end

  def self.fetch_page(url)
    uri = URI.parse(url)

    Net::HTTP.start(uri.host, uri.port,
                    use_ssl: true,
                    open_timeout: OPEN_TIMEOUT,
                    read_timeout: READ_TIMEOUT) do |http|
      request = Net::HTTP::Get.new(uri.request_uri)
      request["User-Agent"] = "CleverBot/1.0 (+link preview)"
      response = http.request(request)
      next nil unless response.is_a?(Net::HTTPSuccess)

      # Bounded so a hostile or merely huge page cannot be pulled into memory.
      response.body.to_s.first(MAX_BYTES)
    end
  rescue StandardError
    nil
  end
end