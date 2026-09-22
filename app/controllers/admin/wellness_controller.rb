module Admin
  # Moderator wellness controls. The panel hands an operator a stream of the
  # worst content on the site, and research on moderation tooling is consistent
  # about two things that reduce the harm that does without hurting accuracy:
  # media blurred behind a deliberate reveal, and a prompt to step away.
  #
  # Both are the operator's own settings, so this controller only ever writes
  # the current user's row. It is deliberately not a page for managing other
  # people: `wellness.manage` is the grant to reach it at all, and the record it
  # changes is always pinned to `current_user`.
  class WellnessController < AdminController
    before_action :require_wellness_permission

    def show
      @setting = ModeratorSetting.for(current_user)
      # The shift clock is only meaningful once someone has started one. Without
      # a start the reminder stays quiet, so an operator who never opted in is
      # never nagged.
      @setting.start_shift! if @setting.shift_started_at.nil?
      @minutes = @setting.minutes_since_break
      @break_due = @setting.break_due?
    end

    # Media blurring is the one control that alternates both ways. It is audited
    # every time, because turning the safety default off is exactly the kind of
    # decision that should be visible later.
    def blur
      setting = ModeratorSetting.for(current_user)
      setting.update!(sensitive_media_blurred: params[:sensitive_media_blurred] != "0")
      audit!("wellness.media_blur", target: "user:#{current_user.id}",
                                    detail: setting.sensitive_media_blurred ? "blurring enabled" : "blurring disabled")
      redirect_to admin_wellness_path,
                  notice: "Sensitive media will be #{setting.sensitive_media_blurred ? 'blurred' : 'shown'} by default."
    end

    def interval
      setting = ModeratorSetting.for(current_user)
      minutes = params[:break_reminder_minutes].to_i
      minutes = ModeratorSetting::DEFAULT_BREAK_MINUTES unless minutes.between?(
        ModeratorSetting::MIN_BREAK_MINUTES, ModeratorSetting::MAX_BREAK_MINUTES
      )
      setting.update!(break_reminder_minutes: minutes)
      audit!("wellness.break_interval", target: "user:#{current_user.id}",
                                        detail: "break reminder every #{minutes} minutes")
      redirect_to admin_wellness_path, notice: "Break reminder set to every #{minutes} minutes."
    end

    def take_break
      ModeratorSetting.for(current_user).take_break!
      audit!("wellness.break", target: "user:#{current_user.id}", detail: "took a break")
      redirect_to admin_wellness_path, notice: "Break recorded. The interval has restarted."
    end

    def snooze
      ModeratorSetting.for(current_user).snooze!
      audit!("wellness.break_snoozed", target: "user:#{current_user.id}",
                                       detail: "snoozed the break reminder")
      redirect_to admin_wellness_path, notice: "Reminder snoozed."
    end

    private

    def require_wellness_permission
      require_permission!("wellness.manage")
    end
  end
end
