require "application_system_test_case"

# The 2019 composer counted the characters down from the limit, turned red past
# it, and held the Tweet button until there was something to send. Both are
# driven by the front-end script, so they are exercised in a real browser: the
# counter and the disabled button are exactly what a selector drift in that
# script silently breaks, and a markup assertion would never catch it.
class ComposerCounterTest < ApplicationSystemTestCase
  setup do
    @user = create_member
    sign_in_as(@user)
  end

  test "the counter starts at the limit with the Tweet button held" do
    visit_composer

    assert_equal limit.to_s, counter_text
    assert tweet_button_disabled?, "the Tweet button was live on an empty composer"
  end

  test "typing counts down and releases the Tweet button" do
    visit_composer
    find(".compose textarea").set("Hello")

    assert_equal (limit - 5).to_s, counter_text
    assert_not tweet_button_disabled?, "the Tweet button stayed disabled with a draft"
  end

  test "going past the limit turns the counter red and holds the button" do
    visit_composer
    # maxlength stops a person typing past the limit, but a paste or an IME can
    # land a longer value, which is the case the red counter exists for.
    page.execute_script(<<~JS)
      var box = document.querySelector('.compose textarea');
      box.value = new Array(#{limit + 2}).join('x');
      box.dispatchEvent(new Event('input', { bubbles: true }));
    JS

    assert_equal "-1", counter_text
    assert_selector ".tweet-counter.over"
    assert tweet_button_disabled?, "the Tweet button was live past the limit"
  end

  private

  # The limit is operator-editable, so read it from the same place the app does
  # rather than baking the default into the assertions.
  def limit
    SiteSetting.get("max_tweet_length").to_i
  end

  def visit_composer
    visit "/home"
    assert_selector ".compose .tweet-counter", wait: 5
  end

  def counter_text
    find(".tweet-counter").text
  end

  def tweet_button_disabled?
    page.evaluate_script("document.querySelector('.compose .tweet-btn').disabled")
  end

  def sign_in_as(user)
    visit "/login"
    fill_in "identifier", with: user.username
    fill_in "password", with: "password123"
    click_button "Log in"
    assert_selector ".timeline, .compose", wait: 5
  end

  def create_member
    User.create!(
      username: "composer_member",
      display_name: "Composer Member",
      email: "composer_member@example.com",
      password_hash: PasswordDigest.hash("password123"),
      role: Role.find_by!(name: "user")
    )
  end
end
