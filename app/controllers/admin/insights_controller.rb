# Read-only analytics over the tables the site already keeps. Nothing here
# writes, so it needs only the admin panel gate and never a confirmation.
module Admin
  class InsightsController < AdminController
    def index
      @totals = {
        users: User.count,
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
      @appeal_metrics = appeal_metrics
      @database_bytes = Maintenance.database_bytes
      @table_weights = Maintenance.table_weights
      @weight_max = @table_weights.map { |_label, count| count }.max.to_i
    end

    private

    # Appeal quality: how often the second look disagrees with the first. A
    # reversed appeal is an overturn; a "modified" one changes the sanction but
    # leaves it standing, so it is not counted as one. Overturn rate is the
    # standard signal for a moderation team, so it is grouped by sanction kind
    # and by the operator who decided, not just shown as one site-wide figure.
    def appeal_metrics
      decided = Appeal.decided
      total = decided.count
      overturned = decided.where(state: "reversed").count

      {
        counts: Appeal::STATES.index_with { |state| Appeal.where(state: state).count },
        total: total,
        overturned: overturned,
        rate: total.zero? ? nil : (overturned * 100.0 / total).round,
        by_sanction: appeal_overturns_by_sanction(decided),
        by_operator: appeal_overturns_by_operator(decided)
      }
    end

    def appeal_overturns_by_sanction(decided)
      Appeal::SANCTIONS.keys.map do |kind|
        rows = decided.where(sanction_kind: kind)
        {
          label: Appeal::SANCTIONS.fetch(kind),
          total: rows.count,
          overturned: rows.where(state: "reversed").count
        }
      end
    end

    def appeal_overturns_by_operator(decided)
      totals = decided.group(:decided_by_id).count
      reversals = decided.where(state: "reversed").group(:decided_by_id).count
      names = User.where(id: totals.keys.compact).pluck(:id, :username).to_h

      totals.map do |operator_id, total|
        {
          operator: names[operator_id],
          total: total,
          overturned: reversals[operator_id].to_i
        }
      end.sort_by { |row| [ -row[:overturned], -row[:total], row[:operator].to_s ] }
    end

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