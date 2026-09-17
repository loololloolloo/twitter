module Admin
  class DashboardController < AdminController
    def index
      @stats = {
        users: User.count,
        suspended: User.where(is_suspended: true).count,
        banned: User.where(is_banned: true).count,
        tweets: Tweet.visible.count,
        likes: Like.count,
        follows: Follow.count,
        notifications: Notification.count
      }

      @roles = Role.order(rank: :desc)
      @permissions = Permission.order(:id)
      @recent = AuditLog.includes(:actor).recent.limit(25)

      @role_user_counts = User.joins(:role).group("roles.name").count
      @role_grants = Role.includes(:permissions).each_with_object({}) do |role, hash|
        hash[role.name] = role.permissions.map(&:key).sort
      end
    end
  end
end