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

      audit!("settings.edit", target: "site", detail: "updated site settings")
      redirect_to admin_settings_path, notice: "Settings saved."
    end

    private

    def require_settings_permission
      require_permission!("settings.edit")
    end
  end
end