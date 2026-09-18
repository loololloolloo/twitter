# The sidebar controls on every admin page - currently the announcement banner.
# It lives in SiteSetting, so it takes effect on the public site as soon as it
# is saved, with no deploy.
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

    private

    def require_settings_permission
      require_permission!("settings.edit")
    end
  end
end
