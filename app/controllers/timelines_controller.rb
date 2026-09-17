class TimelinesController < ApplicationController
  def root
    redirect_to(signed_in? ? home_path : login_path)
  end

  def home
    require_login! || return

    @tweets = home_feed

    @suggestions = User.visible
                       .where.not(id: current_user.id)
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
      newest: rows.map(&:created_at).max&.iso8601(6)
    }
  rescue ArgumentError, TypeError
    # A malformed `after` means "send the latest", not an error.
    render json: { count: 0, html: "", newest: nil }
  end

  def explore
    require_login! || return

    @query = params[:q].to_s.strip
    @trends = Tweet.top_trends

    scope = Tweet.visible.includes(:user, retweet_of: :user).recent

    if @query.present?
      # A leading # narrows to hashtags; an @ narrows to accounts. Both are
      # matched against the stored text, which is how the classic search worked.
      scope = scope.where("body LIKE ?", "%#{@query}%")
    end

    @tweets = scope.limit(60)

    @people =
      if @query.present?
        term = @query.delete_prefix("@").delete_prefix("#")
        User.visible
            .where("username LIKE ? OR display_name LIKE ?", "%#{term}%", "%#{term}%")
            .limit(20)
      else
        User.visible.where.not(id: current_user.id)
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
         .where(retweet_of_id: nil)
         .or(Tweet.visible.where(user_id: followed_ids))
         .or(Tweet.visible.where(user_id: current_user.id))
         .includes(:user, retweet_of: :user)
         .recent
         .limit(120)
  end
end