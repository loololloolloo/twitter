# Controls the long-lived bot runner from the admin panel.
#
# The runner is a separate process, so these actions start and stop it through
# BotRunner rather than doing the work in-request. It is granted on its own
# permission rather than riding on `settings.edit`, because restarting the
# simulation is an operational act distinct from editing site settings.
module Admin
  class BotsController < AdminController
    before_action :require_bot_runner_permission

    def show
      @status = BotRunner.status
      @recent = User.bots.order(last_action_at: :desc).limit(10)
    end

    def start
      result = BotRunner.start!
      audit!("bots.runner.start", target: "bots", detail: "started the bot runner")

      redirect_to admin_bots_path, notice: runner_notice(result, "started")
    end

    def stop
      result = BotRunner.stop!
      audit!("bots.runner.stop", target: "bots", detail: "stopped the bot runner")

      redirect_to admin_bots_path, notice: runner_notice(result, "stopped")
    end

    def restart
      result = BotRunner.restart!
      audit!("bots.runner.restart", target: "bots", detail: "restarted the bot runner")

      redirect_to admin_bots_path, notice: runner_notice(result, "restarted")
    end

    private

    def runner_notice(result, verb)
      case result
      when :started then "Bot runner #{verb}."
      when :stopped then "Bot runner #{verb}."
      when :already_running then "Bot runner was already up."
      when :not_running then "Bot runner was not running."
      else "Bot runner #{verb}; it has not reported a pid yet, check the log below."
      end
    end

    def require_bot_runner_permission
      require_permission!("bots.runner")
    end
  end
end