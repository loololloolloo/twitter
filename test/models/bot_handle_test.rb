require "test_helper"

# BotFactory writes accounts with insert_all, so a generated handle never
# passes through the model's USERNAME_FORMAT validation. These tests pin the
# properties that make a generated handle usable: it validates, and it can be
# reached by the profile route.
class BotHandleTest < ActiveSupport::TestCase
  test "a sanitized handle never contains a period" do
    # A dot is not merely disallowed by the model. It breaks the route:
    # /u/first.last parses as username "first" with format "last", so the
    # profile becomes unreachable. The sanitizer must strip it.
    assert_equal "aaronchen", BotFactory.sanitize_handle("aaron.chen")
    assert_equal "aaronchen", BotFactory.sanitize_handle("aaron...chen")
    assert_equal "aaron_chen", BotFactory.sanitize_handle("aaron_chen")
    assert_equal "aaronchen99", BotFactory.sanitize_handle("aaron.chen.99")

    # The sanitizer expects already-downcased input, which username_for
    # guarantees; anything else is dropped rather than folded.
    assert_equal "user", BotFactory.sanitize_handle("AARON.CHEN")
  end

  test "generated handles are lowercase" do
    taken = Set.new

    500.times do |i|
      handle = BotFactory.username_for(PersonaGenerator.build(50_000 + i), i, taken)
      taken << handle

      assert_equal handle.downcase, handle, "handles should not shout"
    end
  end

  test "generated handles match the model format across many seeds" do
    taken = Set.new

    4_000.times do |i|
      persona = PersonaGenerator.build(70_000 + i)
      handle = BotFactory.username_for(persona, i, taken)
      taken << handle

      assert_match User::USERNAME_FORMAT, handle,
                   "generated handle #{handle.inspect} fails the model's own format"
      assert_operator handle.length, :<=, 15
      refute_includes handle, ".", "a period would make the profile unreachable"
    end
  end

  test "generated handles are unique" do
    taken = Set.new
    handles = 2_000.times.map do |i|
      persona = PersonaGenerator.build(90_000 + i)
      handle = BotFactory.username_for(persona, i, taken)
      taken << handle
      handle
    end

    assert_equal handles.size, handles.uniq.size, "handles must not collide"
  end

  test "a generated handle is reachable by the profile route" do
    persona = PersonaGenerator.build(12_345)
    handle = BotFactory.sanitize_handle("#{persona['first_name']}.#{persona['last_name']}".downcase)

    # The real symptom of the bug: a dotted name routed to the wrong username.
    recognized = Rails.application.routes.recognize_path("/u/#{handle}")

    assert_equal "profiles", recognized[:controller]
    assert_equal handle, recognized[:username]
    assert_nil recognized[:format], "the handle must not be read as a format"
  end

  test "a dotted username cannot be routed to its own profile" do
    # This is why the dot had to go: the route silently truncates the name, so
    # the account exists but its page resolves to a different username.
    recognized = Rails.application.routes.recognize_path("/u/aaron.chen")

    assert_equal "aaron", recognized[:username]
    assert_equal "chen", recognized[:format]
  end
end
