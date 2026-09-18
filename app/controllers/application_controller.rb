class ApplicationController < ActionController::Base
  include BanPolicy

  allow_browser versions: :modern

  helper_method :current_user, :signed_in?, :can?, :site_name, :max_tweet_length,
                :humanize_until, :ban_expiry, :ban_duration_choices,
                :connected_accounts, :impersonating?

  # Controllers that stay reachable while an account is banned. Everything else
  # redirects to the ban screen so the reason and the log out button are never
  # hidden behind a wall.
  BAN_GATE_EXEMPT = %w[sessions registrations banned].freeze

  before_action :load_current_user
  before_action :enforce_ban
  before_action :set_shared_context

  private

  def load_current_user
    @current_user = User.find_by(id: session[:user_id]) if session[:user_id]
    # Reading the record lets an expired timed ban clear itself.
    @current_user&.banned?
  end

  def current_user
    @current_user
  end

  def signed_in?
    current_user.present?
  end

  # True while an operator is browsing as another member. The original operator
  # id is kept in the session for the duration.
  def impersonating?
    session[:impersonator_id].present?
  end

  def can?(key)
    signed_in? && current_user.can?(key)
  end

  # The accounts this browser has signed into, in the order they were added.
  # The sidebar switcher renders them in place rather than sending the member
  # to a separate screen, so the layout needs the list on every page.
  def connected_accounts
    return [] unless signed_in?

    ids = AccountsController.account_ids(session)
    return [] if ids.empty?

    found = User.where(id: ids).index_by(&:id)
    ids.filter_map { |id| found[id] }
  end

  def enforce_ban
    return if current_user.nil?
    return unless current_user.is_banned?
    return if BAN_GATE_EXEMPT.include?(controller_name)

    redirect_to banned_path
  end

  def require_login!
    return true if signed_in?

    redirect_to login_path
    false
  end

  def require_permission!(key)
    return false unless require_login!
    return true if can?(key)

    render plain: "Forbidden", status: :forbidden
    false
  end

  def site_name
    SiteSetting.get("site_name").presence || "Twitter"
  end

  def max_tweet_length
    SiteSetting.get("max_tweet_length").to_i
  end

  def site_tagline
    SiteSetting.get("site_tagline")
  end

  def set_shared_context
    @site_name = site_name
    @site_tagline = site_tagline
    @max_len = max_tweet_length
    @me = current_user
    @my_permissions = signed_in? ? current_user.permission_keys : Set.new
    @trends = Tweet.top_trends if signed_in?
    @announcement = SiteSetting.announcement
  end

  def audit!(action, target: "", detail: "")
    AuditLog.record(actor: current_user, action: action, target: target, detail: detail)
  end
end
