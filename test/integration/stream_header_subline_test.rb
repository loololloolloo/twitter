require "test_helper"

# The 2019 stream header carries a second line under the title: the account or
# context the screen belongs to, in the smaller grey subline. That line is
# styled by `.stream-head-sub`. Several headers marked it instead with a
# `.stream-sub` class that no stylesheet defines, so the line rendered at the
# full heading size and colour next to the title. These assert the styled class
# on every header that carries the line.
class StreamHeaderSublineTest < ActionDispatch::IntegrationTest
  setup do
    @me = create_user(username: "sub_me")
    @other = create_user(username: "sub_other")
    @tweet = Tweet.create!(user: @other, body: "subline body")
    @list = List.create!(user: @me, name: "Reading")
  end

  def assert_subline(path, text)
    get path
    assert_response :success, "#{path} did not render cleanly"
    assert_select ".stream-head .stream-head-title .stream-head-sub", text: text,
                  message: "#{path} did not mark its subline with .stream-head-sub"
    assert_select ".stream-head .stream-sub", count: 0,
                  message: "#{path} still carries the unstyled .stream-sub class"
  end

  test "the lists pages style the list name as the header subline" do
    sign_in @me
    assert_subline lists_path, "@sub_me"
    assert_subline list_path(@list), %r{@sub_me}
    assert_subline list_members_path(@list), "Reading"
    assert_subline edit_list_path(@list), "Reading"
  end

  test "the bookmarks header styles the handle as the subline" do
    sign_in @me
    assert_subline bookmarks_path, "@sub_me"
  end

  test "the quotes header styles the author as the subline" do
    sign_in @me
    assert_subline tweet_quotes_path(@tweet), "@sub_other"
  end

  test "the follow requests header styles the handle as the subline" do
    @me.update!(protected: true)
    sign_in @me
    assert_subline follow_requests_path, "@sub_me"
  end
end
