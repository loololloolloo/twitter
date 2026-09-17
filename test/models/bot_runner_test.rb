require "test_helper"

# The admin panel is the only place the app reaches out of its own process, so
# these exercise `BotRunner` against real short-lived processes rather than a
# stand-in: starting, stopping and detecting a dead runner are all about how the
# operating system reports a process, which a mock would not reproduce.
class BotRunnerTest < ActiveSupport::TestCase
  # A process that writes its own pid file and then sleeps, standing in for the
  # runner the admin panel manages. The real task is not started because it would
  # boot a second copy of the app.
  def sleeper
    script = "File.write(ARGV[0], Process.pid.to_s); sleep 30"
    [ RbConfig.ruby, "-e", script, BotRunner.pid_path.to_s ]
  end

  # A process that exits at once, so the pid file it wrote is left stale.
  def quitter
    script = "File.write(ARGV[0], Process.pid.to_s)"
    [ RbConfig.ruby, "-e", script, BotRunner.pid_path.to_s ]
  end

  setup do
    BotRunner.pid_path.dirname.mkpath
    BotRunner.clear_pid_file
    @started = []
    @stubbed = false
  end

  teardown do
    # Never leave a stray process behind between tests.
    @started.each do |pid|
      Process.kill("KILL", pid)
    rescue Errno::ESRCH
      nil
    end
    if @stubbed
      BotRunner.singleton_class.send(:remove_method, :default_command)
      @stubbed = false
    end
    BotRunner.clear_pid_file
  end

  def track(pid)
    @started << pid if pid
    pid
  end

  # Points the no-argument entry points (`start!`, `restart!`) at the stand-in
  # process, so the admin panel's buttons can be driven directly rather than
  # only the `command:` argument they pass down.
  def stub_runner_command
    # Captured in a local: a block defined on BotRunner is evaluated in the
    # module's context and cannot see this test's methods.
    command = sleeper
    BotRunner.define_singleton_method(:default_command) { command }
    @stubbed = true
  end

  # `stop!` sends SIGTERM and returns as soon as it has been delivered, so the
  # process may take a moment to actually exit. Polls rather than assuming.
  def wait_until_dead(pid, timeout: 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    while BotRunner.alive?(pid)
      return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.05
    end
    true
  end

  # `start!` returns once the task has written its own pid file.
  test "starting reports that the runner came up" do
    assert_equal :started, BotRunner.start!(command: sleeper)
    track BotRunner.pid

    assert BotRunner.running?
  end

  test "the pid is the process that was actually spawned" do
    BotRunner.start!(command: sleeper)
    pid = track BotRunner.pid

    assert pid.positive?
    assert BotRunner.alive?(pid)
  end

  test "a second start leaves the running runner alone" do
    BotRunner.start!(command: sleeper)
    original = track BotRunner.pid

    assert_equal :already_running, BotRunner.start!(command: sleeper)
    assert_equal original, BotRunner.pid, "the running runner should be the one kept"
  end

  test "starting twice does not leave two processes behind" do
    BotRunner.start!(command: sleeper)
    first = track BotRunner.pid
    BotRunner.start!(command: sleeper)

    assert_equal first, BotRunner.pid
    assert BotRunner.alive?(first)
  end

  test "stopping reports the runner was stopped and takes it down" do
    BotRunner.start!(command: sleeper)
    pid = track BotRunner.pid

    assert_equal :stopped, BotRunner.stop!
    refute BotRunner.running?

    # The process is gone, not merely forgotten.
    assert wait_until_dead(pid), "the runner process was still alive after stop!"
  end

  test "stopping leaves the pid file cleared" do
    BotRunner.start!(command: sleeper)
    BotRunner.stop!

    refute BotRunner.pid_path.exist?
  end

  test "stopping when nothing is running says so" do
    assert_equal :not_running, BotRunner.stop!
  end

  test "a pid file left by a dead process is not reported as running" do
    BotRunner.start!(command: quitter)
    # The process has exited, so `wait_for_pid_file` may or may not have caught
    # the file; make the stale state explicit either way.
    File.write(BotRunner.pid_path, "999999")

    refute BotRunner.running?, "a stale pid file should not read as a live runner"
    refute BotRunner.pid_path.exist?, "the stale file should be cleaned up"
  end

  test "an unreadable pid file is treated as no runner" do
    File.write(BotRunner.pid_path, "not a number")

    refute BotRunner.running?
  end

  # `restart!` is the admin panel's button: it must take the old process down
  # before bringing a new one up.
  test "restarting replaces the running process" do
    stub_runner_command
    BotRunner.start!(command: sleeper)
    original = track BotRunner.pid

    assert_equal :started, BotRunner.restart!
    replacement = track BotRunner.pid

    assert replacement.positive?
    refute_equal original, replacement, "restart should not keep the old pid"
    assert wait_until_dead(original), "the old process should be gone"
    assert BotRunner.alive?(replacement)
  end

  test "the admin panel's restart brings a runner up from nothing" do
    refute BotRunner.running?
    stub_runner_command

    assert_equal :started, BotRunner.restart!
    track BotRunner.pid

    assert BotRunner.running?
  end

  test "status reports the population and the panel's figures" do
    create_user(username: "status_human")
    create_user(username: "status_bot", is_bot: true)

    status = BotRunner.status

    assert_equal 1, status[:humans]
    assert_equal 1, status[:population]
    assert_equal BotEngine::DEFAULT_INTERVAL, status[:interval]
    assert_equal BotEngine::DEFAULT_BATCH, status[:batch]
    assert_includes [ true, false ], status[:running]
    assert_kind_of Array, status[:log_tail]
  end

  test "status counts the bots that are due to act" do
    due = create_user(username: "due_bot", is_bot: true)
    due.update_columns(next_action_at: 1.minute.ago)
    later = create_user(username: "later_bot", is_bot: true)
    later.update_columns(next_action_at: 1.hour.from_now)

    assert_equal 1, BotRunner.status[:due]
  end

  test "status totals the actions the population has taken" do
    bot = create_user(username: "busy_bot", is_bot: true)
    bot.update_columns(actions_performed: 12)

    assert_equal 12, BotRunner.status[:actions]
  end

  test "the log tail returns the last lines and no more" do
    BotRunner.log_path.dirname.mkpath
    BotRunner.log_path.write((1..20).map { |i| "line #{i}\n" }.join)

    tail = BotRunner.log_tail(lines: 3)

    assert_equal [ "line 18", "line 19", "line 20" ], tail
  ensure
    BotRunner.log_path.delete if BotRunner.log_path.exist?
  end

  test "the log tail is empty when there is no log yet" do
    BotRunner.log_path.delete if BotRunner.log_path.exist?

    assert_equal [], BotRunner.log_tail
  end
end