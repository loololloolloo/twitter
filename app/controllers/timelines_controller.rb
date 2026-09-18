class TimelinesController < ApplicationController
  def root
    redirect_to(signed_in? ? home_path : login_path)
  end

  def home
    require_login! || return

    # The 2019 home header could order the same timeline two ways: Top Tweets,
    # ranked by engagement, or the latest first. Both are the same stream, so
    # the mode only changes the ordering.
    @show = params[:show].presence_in(%w[top latest]) || "top"

    @tweets =
      if @show == "top"
        # "Top" ranks the same entries by engagement, which is what the header
        # advertised. The scope is capped before sorting so a busy site does not
        # pull every post into memory to rank it.
        home_feed.limit(200).to_a
                 .sort_by { |t| -(t.like_count + t.favourite_count + t.retweet_count + t.reply_count) }
                 .first(120)
      else
        home_feed
      end

    # Suggestions exclude accounts already followed, blocked either way, and
    # muted, so the panel never proposes somebody the reader has silenced.
    @suggestions = User.visible
                       .where.not(id: current_user.id)
                       .where.not(id: current_user.following.select(:id))
                       .where.not(id: current_user.silenced_account_ids)
                       .order(Arel.sql("RANDOM()"))
                       .limit(3)

    @trends = Tweet.top_trends
  end

  # Serves timeline entries newer than the newest one the page already has, so
  # the home feed can refresh itself while it is open. Only the entries are
  # returned, as rendered HTML, because the client just prepends them.
  #
  # The cursor carries microsecond precision. A second-precision timestamp
  # would truncate the newest tweet's time, so that tweet would keep comparing
  # as "newer than the cursor" and be re-sent on every poll.
  def feed
    require_login! || return

    after = params[:after].presence

    tweets = home_feed
    tweets = tweets.where("tweets.created_at > ?", Time.zone.parse(after)) if after

    rows = tweets.reorder(created_at: :desc).limit(30).to_a

    render json: {
      count: rows.size,
      html: render_to_string(partial: "tweets/tweet", collection: rows, formats: [ :html ]),
      newest: rows.map(&:created_at).max&.iso8601(6),
      # Engagement for the entries already on the page, so their counters keep
      # moving while the reader is looking at them. Posts the reader can see are
      # named by the client; anything else is not counted.
      counts: engagement_counts(params[:ids])
    }
  rescue ArgumentError, TypeError
    # A malformed `after` means "send the latest", not an error.
    render json: { count: 0, html: "", newest: nil, counts: {} }
  end

  def explore
    require_login! || return

    @query = params[:q].to_s.strip
    @trends = Tweet.top_trends
    # The 2019 search screen had tabs: Top, Latest, People, Photos and Videos.
    # `top` and `latest` differ in ordering rather than in what they match.
    @tab = params[:tab].presence_in(%w[top latest people photos]) || "top"

    scope = Tweet.visible.readable_by(current_user).includes(:user, retweet_of: :user, quote_of: :user)

    if @query.present?
      # A leading # narrows to hashtags; an @ narrows to accounts. Both are
      # matched against the stored text, which is how the classic search worked.
      term = @query.delete_prefix("@").delete_prefix("#")
      scope = scope.where("tweets.body LIKE ?", "%#{term}%")
      scope = scope.where("tweets.body LIKE ?", "%##{term}%") if @query.start_with?("#")
    end

    @tweets =
      case @tab
      when "latest" then scope.recent.limit(60)
      when "photos" then scope.where.not(media_path: [ nil, "" ]).recent.limit(60)
      else
        # "Top" ranks by engagement rather than recency, which is what the tab
        # advertised: the posts people reacted to, not merely the newest.
        scope.recent.limit(200).to_a
             .sort_by { |t| -(t.like_count + t.favourite_count + t.retweet_count + t.reply_count) }
             .first(60)
      end

    @people =
      if @query.present?
        term = @query.delete_prefix("@").delete_prefix("#")
        User.visible
            .where.not(id: current_user.silenced_account_ids)
            .where("username LIKE ? OR display_name LIKE ?", "%#{term}%", "%#{term}%")
            .limit(20)
      else
        User.visible.where.not(id: current_user.id)
            .where.not(id: current_user.silenced_account_ids)
            .order(Arel.sql("RANDOM()")).limit(10)
      end
  end

  private

  # The home timeline. Original posts from everyone appear, which is what the
  # classic client did: the home page was the site-wide stream. A retweet,
  # however, is an act of the account that retweeted it, so it only shows when
  # you follow that account; otherwise every retweet in the site would be
  # duplicated into your timeline.
  #
  # Your own retweets are included even though you do not follow yourself -
  # without that, retweeting appeared to do nothing on the home page.
  #
  # 120 entries is enough to fill the first screens; the feed endpoint extends
  # it while the page is open.
  def home_feed
    followed_ids = current_user.active_follows.select(:followee_id)

    Tweet.visible
         .readable_by(current_user)
         .where(retweet_of_id: nil)
         .or(Tweet.visible.readable_by(current_user).where(user_id: followed_ids))
         .or(Tweet.visible.readable_by(current_user).where(user_id: current_user.id))
         .includes(:user, retweet_of: :user, quote_of: :user)
         .recent
         .limit(120)
  end

  # Current engagement for a set of tweets the client named, keyed by id.
  #
  # The ids arrive as a comma-separated list from the page, so they are parsed
  # and bounded here rather than trusted: a poll can only ask about posts that
  # exist, and only a page-sized number of them at a time.
  MAX_COUNT_IDS = 120

  def engagement_counts(raw_ids)
    ids = raw_ids.to_s.split(",").filter_map { |id| Integer(id, exception: false) }
    ids = ids.uniq.first(MAX_COUNT_IDS)
    return {} if ids.empty?

    tweets = Tweet.where(id: ids).includes(:user).to_a
    return {} if tweets.empty?

    # One query per reaction table for the whole set, rather than counting per
    # post, so a poll costs a fixed number of queries regardless of page size.
    like_totals = Like.where(tweet_id: ids).group(:tweet_id, :kind).count
    retweet_totals = Tweet.visible.where(retweet_of_id: ids).group(:retweet_of_id).count

    tweets.each_with_object({}) do |tweet, out|
      likes = like_totals[[ tweet.id, Like::LIKE ]].to_i
      favourites = like_totals[[ tweet.id, Like::FAVOURITE ]].to_i
      retweets = retweet_totals[tweet.id].to_i

      # Labels are built here with the same helper the page uses, so a count the
      # poll writes back is formatted exactly like the one it replaced.
      out[tweet.id] = {
        like_count_label: helpers.count_label(tweet.bonus_likes.to_i + likes),
        favourite_count_label: helpers.count_label(tweet.bonus_favourites.to_i + favourites),
        retweet_count_label: helpers.count_label(tweet.bonus_retweets.to_i + retweets),
        reply_count_label: helpers.count_label(tweet.reply_count)
      }
    end
  end
end