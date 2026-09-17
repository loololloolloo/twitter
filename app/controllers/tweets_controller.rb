class TweetsController < ApplicationController
  before_action :require_login!
  before_action :load_tweet, only: [ :show, :retweet, :destroy, :stats ]

  def show
    @replies = @tweet.replies.visible.includes(:user).order(:created_at)
    @ancestors = []
    node = @tweet.parent
    while node
      @ancestors.unshift(node)
      node = node.parent
    end
  end

  # Current engagement for the focused post and its replies, so the permalink
  # keeps counting while it is open. The shape matches what the action endpoints
  # already return, so the client can repaint both the count line and the
  # buttons with the same code.
  def stats
    return if performed?

    render json: stats_payload(@tweet).merge(
      replies: @tweet.replies.visible.order(:created_at).limit(50).map { |reply| stats_payload(reply) }
    )
  end

  def create
    body = params[:body].to_s.strip
    media = params[:media]
    has_media = media.present? && media.respond_to?(:original_filename) && media.original_filename.present?

    if body.empty? && !has_media
      redirect_back fallback_location: home_path, alert: "Your tweet was empty."
      return
    end

    if body.length > max_tweet_length
      redirect_back fallback_location: home_path,
                    alert: "Tweets must be #{max_tweet_length} characters or fewer."
      return
    end

    parent = params[:parent_id].present? ? Tweet.visible.find_by(id: params[:parent_id]) : nil

    # The upload is validated before the tweet is written so a rejected file
    # cannot leave a row pointing at a path that was never stored.
    media_path = Uploads.store(media, current_user.id)

    if has_media && media_path.nil?
      redirect_back fallback_location: home_path, alert: "That image type is not supported."
      return
    end

    tweet = Tweet.create!(user: current_user, body: body, parent: parent, media_path: media_path)

    if parent && parent.user_id != current_user.id
      Notification.create!(user: parent.user, actor: current_user, kind: "reply",
                           tweet: tweet, body: body.first(120))
    end

    MentionScanner.notify(tweet)

    # A post from the account the population is watching is answered at once,
    # rather than waiting for each bot's next scheduled slot.
    BotEngine.rally_to(tweet) if parent.nil?

    if parent
      redirect_to tweet_path(parent)
    else
      redirect_back fallback_location: home_path
    end
  end

  def retweet
    if @tweet.user_id == current_user.id
      return action_refused("You cannot retweet your own tweet.")
    end

    if @tweet.retweet_of_id
      return action_refused("That is already a retweet.")
    end

    # Toggling: a second click on a live retweet removes it, which is what the
    # button advertises by switching to "Retweeted".
    existing = Tweet.visible.find_by(user_id: current_user.id, retweet_of_id: @tweet.id)
    if existing
      existing.update!(is_deleted: true)
      return action_done(notice: "Retweet undone.", retweeted: false)
    end

    Tweet.create!(user: current_user, body: "", retweet_of: @tweet)

    if @tweet.user_id != current_user.id
      Notification.create!(user: @tweet.user, actor: current_user, kind: "retweet",
                           tweet: @tweet, body: "@#{current_user.username} retweeted your tweet")
    end

    action_done(notice: "Retweeted.", retweeted: true)
  end

  # A toggle is answered with the tweet's new state so the page can repaint the
  # button in place. The plain redirect is kept for a browser without the
  # script, so the control still works when JavaScript is unavailable.
  def action_done(notice:, retweeted:)
    respond_to do |format|
      format.html { redirect_back fallback_location: tweet_path(@tweet), notice: notice }
      format.json do
        render json: {
          id: @tweet.id,
          retweeted: retweeted,
          retweet_count: @tweet.retweet_count,
          retweet_count_label: helpers.count_label(@tweet.retweet_count),
          liked: @tweet.liked_by?(current_user),
          like_count: @tweet.like_count,
          like_count_label: helpers.count_label(@tweet.like_count),
          favourited: @tweet.favourited_by?(current_user),
          favourite_count: @tweet.favourite_count,
          favourite_count_label: helpers.count_label(@tweet.favourite_count),
          reply_count: @tweet.reply_count,
          reply_count_label: helpers.count_label(@tweet.reply_count)
        }
      end
    end
  end

  def action_refused(message)
    respond_to do |format|
      format.html { redirect_to tweet_path(@tweet), alert: message }
      format.json { render json: { error: message }, status: :unprocessable_entity }
    end
  end

  def destroy
    unless @tweet.user_id == current_user.id || can?("tweets.delete")
      redirect_to tweet_path(@tweet), alert: "You cannot delete that tweet."
      return
    end

    @tweet.update!(is_deleted: true)
    audit!("tweet.delete", target: "tweet:#{@tweet.id}", detail: "Deleted tweet #{@tweet.id}")

    redirect_to(home_path)
  end

  private

  def load_tweet
    @tweet = Tweet.visible.includes(:user, retweet_of: :user).find_by(id: params[:id])
    return if @tweet

    render plain: "Not found", status: :not_found
  end

  # One post's engagement, in the same shape the action endpoints return, so
  # the permalink's poll can repaint counts and buttons the same way.
  def stats_payload(tweet)
    {
      id: tweet.id,
      like_count: tweet.like_count,
      like_count_label: helpers.count_label(tweet.like_count),
      favourite_count: tweet.favourite_count,
      favourite_count_label: helpers.count_label(tweet.favourite_count),
      retweet_count: tweet.retweet_count,
      retweet_count_label: helpers.count_label(tweet.retweet_count),
      reply_count: tweet.reply_count,
      reply_count_label: helpers.count_label(tweet.reply_count)
    }
  end
end