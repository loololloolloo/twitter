require "test_helper"

# The admin screen that controls the runner. `BotRunner` is stubbed here because
# the real thing spawns a separate process; the process handling itself is
# covered in `BotRunnerTest`. What these pin is the gating, the wiring of each
# button to the right call, and the feedback the operator sees.
class AdminBotsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user(username: "root_admin", role: "owner")
    @member = create_user(username: "plain_member")
    @calls = []
    stub_runner
  end

  teardown do
    # Hand the real methods back so every other test sees the real runner.
    %i[start! stop! restart!].each do |name|
      BotRunner.singleton_class.send(:remove_method, name) if @stubbed&.include?(name)
      BotRunner.singleton_class.send(:define_method, name, @originals[name])
    end
  end

  # Records which runner call was made and returns a chosen outcome, standing in
  # for the separate process.
  def stub_runner(results = {})
    @originals ||= %i[start! stop! restart!].to_h { |n| [ n, BotRunner.method(n) ] }
    @stubbed = []
    this = self
    {
      start!: -> { this.record(:start); results.fetch(:start, :started) },
      stop!: -> { this.record(:stop); results.fetch(:stop, :stopped) },
      restart!: -> { this.record(:restart); results.fetch(:restart, :started) }
    }.each do |name, body|
      BotRunner.define_singleton_method(name, &body)
      @stubbed << name
    end
  end

  def record(name)
    @calls << name
  end

  def signed_in(user)
    post login_path, params: { identifier: user.username, password: "password123" }
    assert_response :redirect
  end

  test "the bots screen is reachable by an admin" do
    signed_in(@admin)

    get admin_bots_path

    assert_response :success
    assert_select "h2", /Runner log/
  end

  test "a signed-out visitor is sent to the login" do
    get admin_bots_path

    assert_response :redirect
    assert_match %r{/login}, response.location
  end

  test "an ordinary member cannot reach the bots screen" do
    signed_in(@member)

    get admin_bots_path

    assert_response :redirect
  end

  test "the screen lists the population's recent activity" do
    bot = create_user(username: "shown_bot", is_bot: true)
    bot.update_columns(last_action_at: Time.current)
    signed_in(@admin)

    get admin_bots_path

    assert_response :success
    assert_match(/shown_bot/i, response.body)
  end

  test "starting the runner calls start and reports it" do
    signed_in(@admin)

    post admin_start_bots_path

    assert_response :redirect
    assert_equal [ :start ], @calls
    follow_redirect!
    assert_match(/started/i, response.body)
  end

  test "starting an already-running runner says so" do
    stub_runner(start: :already_running)
    signed_in(@admin)

    post admin_start_bots_path
    follow_redirect!

    assert_match(/already/i, response.body)
  end

  test "stopping the runner calls stop and reports it" do
    signed_in(@admin)

    post admin_stop_bots_path

    assert_equal [ :stop ], @calls
    follow_redirect!
    assert_match(/stopped/i, response.body)
  end

  test "stopping a runner that is not up says so" do
    stub_runner(stop: :not_running)
    signed_in(@admin)

    post admin_stop_bots_path
    follow_redirect!

    assert_match(/not running/i, response.body)
  end

  test "restarting the runner calls restart and reports it" do
    signed_in(@admin)

    post admin_restart_bots_path

    assert_equal [ :restart ], @calls
    follow_redirect!
    assert_match(/restarted/i, response.body)
  end

  test "an unconfirmed start tells the operator to check the log" do
    stub_runner(start: :unconfirmed)
    signed_in(@admin)

    post admin_start_bots_path
    follow_redirect!

    assert_match(/log/i, response.body)
  end

  test "each button is recorded in the audit trail" do
    signed_in(@admin)

    assert_difference -> { AuditLog.where(action: "bots.runner.start").count }, 1 do
      post admin_start_bots_path
    end
    assert_difference -> { AuditLog.where(action: "bots.runner.stop").count }, 1 do
      post admin_stop_bots_path
    end
    assert_difference -> { AuditLog.where(action: "bots.runner.restart").count }, 1 do
      post admin_restart_bots_path
    end
  end

  test "a member without the permission cannot drive the runner" do
    signed_in(@member)

    post admin_restart_bots_path

    assert_response :redirect
    assert_empty @calls, "a member should not be able to restart the runner"
  end
end