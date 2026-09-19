require "test_helper"

# Resolving a pasted GIF link decides what URL ends up inside a post other
# people load, so the interesting cases are the ones that must be refused:
# a non-image, a non-allowlisted host, and anything that is not http(s).
class GifLinkTest < ActiveSupport::TestCase
  test "a direct media link on an allowlisted host is used as-is" do
    url = "https://media.tenor.com/abc/good.gif"
    assert_equal url, GifLink.resolve(url)
    assert_equal "https://c.tenor.com/xyz/other.webp",
                 GifLink.resolve("https://c.tenor.com/xyz/other.webp")
  end

  test "a scheme-less link is treated as https" do
    assert_equal "https://media.tenor.com/abc/good.gif",
                 GifLink.resolve("media.tenor.com/abc/good.gif")
    assert_equal "https://media.tenor.com/abc/good.gif",
                 GifLink.resolve("//media.tenor.com/abc/good.gif")
  end

  test "a Giphy page link is reduced to its direct asset" do
    assert_equal "https://media.giphy.com/media/3o7aD2saalBwwftBI/giphy.gif",
                 GifLink.resolve("https://giphy.com/gifs/cat-happy-3o7aD2saalBwwftBI")
  end

  test "a Tenor page link is resolved from the page's Open Graph image" do
    html = <<~HTML
      <html><head>
      <meta property="og:image" content="https://media.tenor.com/abc/tenor.gif">
      </head></html>
    HTML

    fetcher = ->(_url) { html }
    assert_equal "https://media.tenor.com/abc/tenor.gif",
                 GifLink.resolve("https://tenor.com/view/hello-gif-12345", fetcher: fetcher)
  end

  test "a Tenor page whose Open Graph image is off-allowlist is refused" do
    html = '<meta property="og:image" content="https://evil.example/tracker.gif">'
    fetcher = ->(_url) { html }

    assert_nil GifLink.resolve("https://tenor.com/view/x-gif-1", fetcher: fetcher)
  end

  test "a page that cannot be read is refused rather than failing the request" do
    assert_nil GifLink.resolve("https://tenor.com/view/x-gif-1", fetcher: ->(_url) { nil })
  end

  test "a host that is not allowlisted is refused" do
    assert_nil GifLink.resolve("https://example.com/not-a-gif.gif")
    assert_nil GifLink.resolve("https://media.tenor.com.evil.example/a.gif")
  end

  test "a non-media path on an allowlisted host is refused" do
    assert_nil GifLink.resolve("https://media.tenor.com/abc/redirect.php")
  end

  test "a non-http scheme is refused" do
    assert_nil GifLink.resolve("javascript:alert(1)")
    assert_nil GifLink.resolve("data:image/gif;base64,R0lGOD")
    assert_nil GifLink.resolve("ftp://media.tenor.com/a.gif")
  end

  test "blank and over-long input is refused" do
    assert_nil GifLink.resolve("")
    assert_nil GifLink.resolve(nil)
    assert_nil GifLink.resolve("https://media.tenor.com/" + "a" * 3_000 + ".gif")
  end
end