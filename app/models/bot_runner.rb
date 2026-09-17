# Starts, stops and reports on the long-lived bot runner.
#
# The runner is the `bots:run` rake task, a process separate from the web
# server, so this is the one place the app reaches out of its own process. The
# pid file is the source of truth for whether it is up: it is written by the
# task itself, so a runner started from a shell and one started from the admin
# panel are tracked the same way.
module BotRunner
  PID_FILE = "tmp/pids/bots_run.pid".freeze
  LOG_FILE = "log/bots_run.log".freeze

  # How long to wait for a freshly spawned task to write its pid file. The task
  # has to boot the whole Rails environment first, which takes a moment.
  PID_WAIT = 20.seconds

  class << self
    def pid_path
      Rails.root.join(PID_FILE)
    end

    def log_path
      Rails.root.join(LOG_FILE)
    end

    # The running task's pid, or nil when it is not up. A pid file left behind
    # by a process that has since died is cleaned up rather than reported as a
    # live runner.
    def pid
      return nil unless pid_path.exist?

      recorded = pid_path.read.strip.to_i
      return nil unless recorded.positive?

      if alive?(recorded)
        recorded
      else
        clear_pid_file
        nil
      end
    end

    def running?
      !pid.nil?
    end

    # True when the process exists. Signal 0 performs the permission and
    # existence checks without delivering anything.
    def alive?(process_id)
      Process.kill(0, process_id)
      true
    rescue Errno::ESRCH, Errno::ERANGE
      false
    rescue Errno::EPERM
      # Alive, but owned by another user. It is still running, which is what
      # the caller asked.
      true
    end

    # Starts the runner if it is not already up. Returns :started or
    # :already_running so the caller can say which happened.
    #
    # `command` is the runner to launch and exists so the behaviour can be
    # exercised against a real short-lived process in tests.
    def start!(command: default_command)
      return :already_running if running?

      clear_pid_file
      FileUtils.mkdir_p(pid_path.dirname)
      FileUtils.mkdir_p(log_path.dirname)

      # The task writes its own pid file, so nothing is written here - that
      # keeps one source of truth. Its output is redirected rather than
      # inherited, or the runner would hold the web server's log open.
      process_id = Process.spawn(
        *command,
        chdir: Rails.root.to_s,
        out: [ log_path.to_s, "a" ],
        err: [ log_path.to_s, "a" ],
        pgroup: true
      )
      Process.detach(process_id)

      wait_for_pid_file ? :started : :unconfirmed
    end

    # Stops the runner with SIGTERM, which the task traps so it can finish its
    # current tick rather than being cut off mid-write.
    def stop!
      process_id = pid
      return :not_running if process_id.nil?

      Process.kill("TERM", process_id)
      clear_pid_file
      :stopped
    rescue Errno::ESRCH
      clear_pid_file
      :not_running
    end

    def restart!
      stop!
      start!
    end

    def clear_pid_file
      # `delete` rather than a delete-if-exists check: the file can vanish
      # between the two calls, both here and in the real runner, which removes
      # its own pid file as it exits.
      pid_path.delete
    rescue Errno::ENOENT
      nil
    end

    def default_command
      [ Rails.root.join("bin/rails").to_s, "bots:run" ]
    end

    # A snapshot for the admin screen: whether it is up, how the population is
    # keeping up, and the tail of its log.
    def status
      {
        running: running?,
        pid: pid,
        population: User.bots.count,
        humans: User.humans.count,
        due: User.bots.where("next_action_at IS NULL OR next_action_at <= ?", Time.current).count,
        actions: User.bots.sum(:actions_performed),
        last_action_at: User.bots.maximum(:last_action_at),
        interval: BotEngine::DEFAULT_INTERVAL,
        batch: BotEngine::DEFAULT_BATCH,
        log_tail: log_tail
      }
    end

    # The last few lines the runner printed. Read from the end so a long-lived
    # runner's log does not have to be loaded whole.
    def log_tail(lines: 12)
      return [] unless log_path.exist?

      content = log_path.read
      content.lines.last(lines).map(&:chomp)
    rescue Errno::ENOENT
      []
    end

    private

    def wait_for_pid_file
      deadline = PID_WAIT.from_now
      sleep 0.1 until pid_path.exist? || Time.current > deadline

      pid_path.exist?
    end
  end
end