require "test_helper"

# 2019 supported pictures, video and GIFs in a post, and the tabbed search
# screen carried a Videos tab. These cover the three ways an attachment can be
# added and the tab that finds one, since a mis-set attachment renders as a
# broken image rather than as an error.
class MediaAttachmentsTest < ActionDispatch::IntegrationTest
  setup do
    @me = create_user(username: "media_me")
    @other = create_user(username: "media_other")
    sign_in @me
  end

  # Uploads reads only the extension, so the bytes stand in for the real file.
  def upload_file(name, bytes = "data")
    path = Rails.root.join("tmp", "media-test-#{name}")
    FileUtils.mkdir_p(path.dirname)
    File.binwrite(path, bytes)
    Rack::Test::UploadedFile.new(path, "application/octet-stream")
  end

  test "the composer offers image, GIF and video" do
    get home_path
    assert_response :success

    assert_match(%r{accept="image/\*,video/mp4}, response.body, "the media picker should accept video")
    assert_match "data-gif-open", response.body, "the composer should offer a GIF control"
    assert_match "data-gif-panel", response.body, "the composer should carry a GIF panel"
    assert_match "data-gif-file", response.body, "the GIF panel should accept a file"
    assert_match(%r{name="gif_url"}, response.body, "the GIF panel should accept a link")
  end

  test "a video is accepted and rendered as a player rather than an image" do
    post compose_path, params: { body: "clip", media: upload_file("clip.mp4") }
    assert_response :redirect

    tweet = Tweet.visible.find_by(user: @me)
    assert tweet.media_attached?
    assert tweet.video?, "an mp4 should be recognised as a video"
    assert_equal "video/mp4", Uploads.content_type(tweet.media_path)

    get tweet_path(tweet)
    assert_response :success
    assert_match "tweet-video", response.body
    assert_match "<video", response.body
    assert_match %r{type="video/mp4"}, response.body
    assert_no_match(
      %r{<img src="/uploads/#{Regexp.escape(tweet.media_path)}},
      response.body, "a video must not be rendered as an image"
    )
  end

  test "a picture is still rendered as an image" do
    post compose_path, params: { body: "still", media: upload_file("still.png") }
    tweet = Tweet.visible.find_by(user: @me)
    refute tweet.video?, "a png is not a video"

    get tweet_path(tweet)
    assert_response :success
    assert_match %r{<img src="/uploads/#{Regexp.escape(tweet.media_path)}"}, response.body
    assert_no_match(/<video/, response.body)
  end

  test "an unsupported file type is refused and nothing is stored" do
    post compose_path, params: { body: "nope", media: upload_file("clip.avi") }
    assert_response :redirect
    assert_match(/not supported/, flash[:alert].to_s)
    assert_nil Tweet.visible.find_by(user: @me)
  end

  test "a GIF can be attached as a file" do
    post compose_path, params: { body: "gif", gif_file: upload_file("loop.gif", "GIF89a") }
    assert_response :redirect

    tweet = Tweet.visible.find_by(user: @me)
    assert tweet.media_attached?
    assert_match(/\.gif\z/, tweet.media_path)

    get tweet_path(tweet)
    assert_match "tweet-media", response.body
  end

  test "a GIF can be attached by pasting a link" do
    post compose_path,
         params: { body: "gif from a link", gif_url: "https://media.tenor.com/abc123/hello.gif" }
    assert_response :redirect

    tweet = Tweet.visible.find_by(user: @me)
    assert tweet.media_attached?
    assert_equal "https://media.tenor.com/abc123/hello.gif", tweet.media_url
    assert_nil tweet.media_path, "a linked GIF should not be copied to disk"

    get tweet_path(tweet)
    assert_match "https://media.tenor.com/abc123/hello.gif", response.body
  end

  test "a Giphy page link is reduced to its direct asset" do
    post compose_path,
         params: { body: "giphy", gif_url: "https://giphy.com/gifs/cat-happy-3o7aD2saalBwwftBI" }
    assert_response :redirect

    tweet = Tweet.visible.find_by(user: @me)
    assert_equal "https://media.giphy.com/media/3o7aD2saalBwwftBI/giphy.gif", tweet.media_url
  end

  test "a link that cannot be embedded is refused" do
    post compose_path, params: { body: "bad", gif_url: "https://example.com/not-a-gif.gif" }
    assert_response :redirect

    assert_match(/could not be used/, flash[:alert].to_s)
    assert_nil Tweet.visible.find_by(user: @me)
  end

  test "an empty post with neither a body nor an attachment is refused" do
    post compose_path, params: { body: "" }
    assert_response :redirect
    assert_match(/empty/, flash[:alert].to_s)
  end

  test "the Videos tab lists videos and leaves pictures out" do
    post compose_path, params: { body: "a clip", media: upload_file("clip.webm") }
    video = Tweet.visible.find_by(user: @me)
    post compose_path, params: { body: "a still", media: upload_file("still2.png") }
    picture = Tweet.visible.where(user: @me).where.not(id: video.id).first

    get explore_path(q: "a", tab: "videos")
    assert_response :success
    assert_match tweet_path(video), response.body
    assert_no_match(/#{Regexp.escape(tweet_path(picture))}/, response.body)

    # The Videos tab is reachable from the other tabs; on Videos itself it is
    # the active label rather than a link.
    get explore_path(q: "a", tab: "photos")
    assert_match %r{href="/explore\?[^"]*tab=videos}, response.body

    get explore_path(q: "a", tab: "videos")
    assert_match "pt-item is-active", response.body
    assert_no_match(%r{href="/explore\?[^"]*tab=videos}, response.body)
  end

  test "the Photos tab keeps a linked GIF" do
    post compose_path,
         params: { body: "linked gif", gif_url: "https://media.tenor.com/abc123/hi.gif" }
    tweet = Tweet.visible.find_by(user: @me)

    get explore_path(q: "linked", tab: "photos")
    assert_response :success
    assert_match tweet_path(tweet), response.body
  end

  test "the profile media grid marks a video with a play badge" do
    post compose_path, params: { body: "profile clip", media: upload_file("mine.mp4") }
    post compose_path, params: { body: "profile still", media: upload_file("mine.png") }

    get profile_path(@me.username, tab: "media")
    assert_response :success
    assert_match "media-cell-video", response.body
    assert_match "media-play", response.body
  end

  # The composer's two media controls belong in one left-aligned group. When
  # each button took `margin-right: auto` for itself the GIF button was pushed
  # across to the Tweet button, so the group element is what is asserted here.
  test "the composer keeps both media controls in one toolbar group" do
    get home_path
    assert_response :success

    tools = response.body[/<div class="compose-tools">.*?<\/div>/m]
    assert_not_nil tools, "the media controls should share a compose-tools group"
    assert_match "data-media-input", tools
    assert_match "data-gif-open", tools
  end
end