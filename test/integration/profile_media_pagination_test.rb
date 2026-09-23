require "test_helper"

# The profile media grid is the one panel that grows without bound, so it fills
# a page at a time. These cover the two things that matter about that: the count
# on screen is bounded, and the account's visibility rules still decide what is
# on the grid once it is fetched by page rather than in one response.
class ProfileMediaPaginationTest < ActionDispatch::IntegrationTest
  setup do
    @me = create_user(username: "viewer_two", display_name: "Viewer Two")
    @subject = create_user(username: "prolific_one", display_name: "Prolific Person")
    sign_in(@me)
  end

  def post_media(count, user: @subject, prefix: "grid")
    count.times do |i|
      Tweet.create!(user: user, body: "#{prefix} #{i}", media_path: "media/#{prefix}_#{i}.png")
    end
  end

  test "the first media page renders one page and offers the next" do
    post_media(65)

    get profile_path(@subject.username, tab: "media")

    assert_response :success
    assert_equal 60, response.body.scan(/class="media-cell"/).size
    assert_match(/data-media-more/, response.body)
    assert_match(/Load more/, response.body)
    assert_match(/page=2/, response.body)
    assert_match(/data-media-url="\/u\/prolific_one\/media"/, response.body)
  end

  # The link has to work without the script, so asking for page 2 renders
  # everything up to page 2 rather than replacing the grid with the tail.
  test "following Load more without JavaScript extends the grid" do
    post_media(65)

    get profile_path(@subject.username, tab: "media", page: 2)

    assert_response :success
    assert_equal 65, response.body.scan(/class="media-cell"/).size
    assert_match(/data-media-more hidden/, response.body)
  end

  test "the last page carries no Load more control" do
    post_media(10)

    get profile_path(@subject.username, tab: "media")

    assert_response :success
    assert_equal 10, response.body.scan(/class="media-cell"/).size
    assert_match(/data-media-more hidden/, response.body)
  end

  test "the pagination endpoint returns only the requested page" do
    post_media(65)

    get profile_media_path(@subject.username), params: { page: 1 }

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal 60, payload["html"].scan(/class="media-cell"/).size
    assert_equal 2, payload["next_page"]
  end

  test "the pagination endpoint reports the end of the grid" do
    post_media(10)

    get profile_media_path(@subject.username), params: { page: 2 }

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal 0, payload["html"].scan(/class="media-cell"/).size
    assert_nil payload["next_page"]
  end

  # A blocked viewer must get the same empty answer from the page fetch as they
  # would from the tab, or the endpoint becomes a way around the block.
  test "the pagination endpoint hides a blocked account's media" do
    post_media(65)
    @me.blocks.create!(blocked: @subject)

    get profile_media_path(@subject.username), params: { page: 1 }

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal 0, payload["html"].scan(/class="media-cell"/).size
    assert_nil payload["next_page"]
  end

  test "a banned account's media stays off the pagination endpoint" do
    post_media(65)
    @subject.update!(is_banned: true, ban_permanent: true)

    get profile_media_path(@subject.username), params: { page: 1 }

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal 0, payload["html"].scan(/class="media-cell"/).size
  end

  # A protected account's grid is open to its approved followers and nobody
  # else, and the endpoint has to agree with the tab about that.
  test "a protected account's media is withheld from a non-follower" do
    post_media(65)
    @subject.update!(protected: true)

    get profile_media_path(@subject.username), params: { page: 1 }

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal 0, payload["html"].scan(/class="media-cell"/).size

    Follow.create!(follower: @me, followee: @subject)

    get profile_media_path(@subject.username), params: { page: 1 }
    assert_equal 60, JSON.parse(response.body)["html"].scan(/class="media-cell"/).size
  end

  test "the grid is ordered newest first across pages" do
    post_media(65)
    newest = Tweet.where(user: @subject).recent.first

    get profile_path(@subject.username, tab: "media", page: 1)

    assert_response :success
    assert_match(/href="#{tweet_path(newest)}"/, response.body)
  end
end
