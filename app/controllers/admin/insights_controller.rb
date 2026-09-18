# Read-only analytics over the tables the site already keeps. Nothing here
# writes, so it needs only the admin panel gate and never a confirmation.
module Admin
  class InsightsController < AdminController
    def index
      @totals = {
        users: User.count,
        humans: User.humans.count,
        bots: User.bots.count,
        verified: User.where(is_verified: true).count,
        suspended: User.where(is_suspended: true).count,
        banned: User.where(is_banned: true).count,
        tweets: Tweet.count,
        replies: Tweet.where.not(parent_id: nil).count,
        retweets: Tweet.where.not(retweet_of_id: nil).count,
        media: Tweet.where.not(media_path: [ nil, "" ]).count,
        likes: Like.where(kind: Like::LIKE).count,
        favourites: Like.where(kind: Like::FAVOURITE).count,
        follows: Follow.count,
        messages: DmMessage.count,
        reports_open: Report.open.count
      }

      @signup_series = signup_series
      @activity_series = activity_series
      @top_accounts = top_accounts
      @top_posts = top_posts
      @database_bytes = Maintenance.database_bytes
      @table_weights = Maintenance.table_weights
      @weight_max = @table_weights.map { |_label, count| count }.max.to_i
    end

    private

    # New accounts per day for the last two weeks, as [date, count] pairs. Days
    # with no signups are filled in so the chart has an unbroken axis.
    def signup_series
      days = (13.downto(0)).map { |offset| Date.current - offset.days }
      counts = User.where(created_at: 13.days.ago.beginning_of_day..)
                   .group("DATE(created_at)").count
      days.map { |day| [ day, counts[day.to_s].to_i ] }
    end

    # Posts per day over the same window.
    def activity_series
      days = (13.downto(0)).map { |offset| Date.current - offset.days }
      counts = Tweet.where(created_at: 13.days.ago.beginning_of_day..)
                    .group("DATE(created_at)").count
      days.map { |day| [ day, counts[day.to_s].to_i ] }
    end

    # The accounts with the most followers, including the granted padding, so
    # the figure matches what the profile shows.
    def top_accounts
      User.includes(:role)
          .sort_by { |user| -user.follower_count }
          .first(10)
    end

    # The posts with the most likes, by the same blended count the timeline
    # renders.
    def top_posts
      Tweet.includes(:user)
           .sort_by { |tweet| -tweet.like_count }
           .first(10)
    end
  end
end