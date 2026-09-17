# The sidebar controls on every admin page - the announcement banner and the
# hide-bots switch. Both live in SiteSetting, so they take effect on the public
# site as soon as they are saved, with no deploy.
module Admin
  class SidebarController < AdminController
    before_action :require_settings_permission

    def update_announcement
      SiteSetting.put("announcement", params[:announcement].to_s.strip[0, 280])

      audit!("settings.announcement", target: "site",
             detail: SiteSetting.announcement.present? ? "posted an announcement" : "cleared the announcement")
      redirect_back fallback_location: admin_root_path,
                    notice: SiteSetting.announcement.present? ? "Announcement posted." : "Announcement cleared."
    end

    def toggle_bots
      SiteSetting.put("hide_bots", SiteSetting.hide_bots? ? "0" : "1")

      audit!("settings.hide_bots", target: "site",
             detail: SiteSetting.hide_bots? ? "hid bots from the site" : "showed bots on the site")
      redirect_back fallback_location: admin_root_path,
                    notice: SiteSetting.hide_bots? ? "Bots are now hidden from the site." : "Bots are visible again."
    end

    private

    def require_settings_permission
      require_permission!("settings.edit")
    end
  end
end
