class BannedController < ApplicationController
  def show
    @ban = current_user

    unless @ban&.is_banned?
      redirect_to(signed_in? ? home_path : login_path)
      return
    end

    @until = @ban.ban_permanent? ? "" : humanize_until(@ban.ban_expires_at)
  end
end