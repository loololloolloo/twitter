require "test_helper"

# Tweet bodies are escaped exactly once on the way out, and the linkifying of
# @mentions and #hashtags must not run over the escapes it produces. Escaping
# the whole body first meant `I'm` became `I&#39;m` and the hashtag pattern then
# matched `#39` inside that entity, so the reader saw the literal `&#39;`.
class TweetTextEscapingTest < ActionDispatch::IntegrationTest
  setup do
    @me = create_user(username: "escaper", role: "owner")
    sign_in(@me)
  end

  # What the browser would actually display: tags removed, entities decoded.
  def visible_text_of_first_tweet
    html = response.body[/<p class="tweet-text">(.*?)<\/p>/m, 1].to_s
    CGI.unescapeHTML(html.gsub(/<[^>]+>/, ""))
  end

  test "an apostrophe is displayed as an apostrophe" do
    post compose_path, params: { body: "I'm wil'in?" }

    tweet = Tweet.where(user_id: @me.id).order(:id).last
    assert_equal "I'm wil'in?", tweet.body, "the body was altered before it was stored"

    get home_path
    assert_response :success
    assert_equal "I'm wil'in?", visible_text_of_first_tweet
  end

  test "an apostrophe is not turned into a hashtag link" do
    post compose_path, params: { body: "I'm wil'in?" }

    get home_path
    assert_response :success

    # `&#39;` must stay a single entity, not be split by a link.
    assert_no_match(/&<a [^>]*>#39<\/a>;/, response.body)
    assert_select "p.tweet-text a.hashtag", false,
                  "the digits of an HTML entity were linked as a hashtag"
  end

  test "real mentions and hashtags are still linked" do
    other = create_user(username: "bob")
    post compose_path, params: { body: "hi @bob about #ruby and #39" }

    get home_path
    assert_response :success

    assert_select "p.tweet-text a.mention[href='#{profile_path(other.username)}']", text: "@bob"
    assert_select "p.tweet-text a.hashtag[href='#{explore_path(q: '#ruby')}']", text: "#ruby"
    assert_select "p.tweet-text a.hashtag[href='#{explore_path(q: '#39')}']", text: "#39"
    assert_equal "hi @bob about #ruby and #39", visible_text_of_first_tweet
  end

  test "markup typed as text is escaped rather than rendered" do
    post compose_path, params: { body: "<script>alert(1)</script>" }

    get home_path
    assert_response :success

    assert_no_match(/<script>alert\(1\)<\/script>/, response.body)
    assert_equal "<script>alert(1)</script>", visible_text_of_first_tweet
  end

  test "an ampersand is not double-escaped" do
    post compose_path, params: { body: "Tom & Jerry" }

    get home_path
    assert_response :success

    assert_no_match(/&amp;amp;/, response.body)
    assert_equal "Tom & Jerry", visible_text_of_first_tweet
  end
end