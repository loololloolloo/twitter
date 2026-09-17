module Admin
  class SettingsController < AdminController
    before_action :require_settings_permission

    def edit
      @settings = SiteSetting.order(:key).pluck(:key, :value).to_h
    end

    def update
      SiteSetting.put("site_name", params[:site_name].to_s.strip.presence || "Twitter")
      SiteSetting.put("site_tagline", params[:site_tagline].to_s.strip.presence || "What's happening?")

      max_len = params[:max_tweet_length].to_s.strip
      max_len = "140" unless max_len.match?(/\A\d{1,4}\z/)
      SiteSetting.put("max_tweet_length", max_len)

      # The checkbox omits the key entirely when unchecked.
      SiteSetting.put("registration_open", params[:registration_open] ? "1" : "0")

      save_simulation_settings

      audit!("settings.edit", target: "site", detail: "updated site settings")
      redirect_to admin_settings_path, notice: "Settings saved."
    end

    private

    def save_simulation_settings
      # The watched account: a post from this handle is answered by the whole
      # simulated population. A blank box falls back to the built-in default so
      # the field cannot be emptied into a name that matches nobody.
      watched = params[:spotlight_username].to_s.strip.delete_prefix("@")
      watched = BotEngine::SPOTLIGHT_DEFAULT unless watched.match?(User::USERNAME_FORMAT)
      SiteSetting.put(BotEngine::SPOTLIGHT_SETTING, watched)

      # Growth rates. Zero is meaningful here - it turns growth off - so the
      # digits are validated rather than replaced by the default.
      { BotEngine::GROWTH_POST_SETTING => BotEngine::GROWTH_PER_POST,
        BotEngine::GROWTH_TICK_SETTING => BotEngine::GROWTH_PER_TICK }.each do |key, fallback|
        value = params[key.to_sym].to_s.strip
        value = fallback.to_s unless value.match?(/\A\d{1,9}\z/)
        SiteSetting.put(key, value)
      end

      # The engine memoises the watched account for a few seconds, so drop it
      # rather than making the operator wait for the change to take effect.
      BotEngine.reset_spotlight!
    end

    def require_settings_permission
      require_permission!("settings.edit")
    end
  end
end