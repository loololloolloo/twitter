class LikesController < ApplicationController
  before_action :require_login!
  before_action :load_tweet
  before_action :set_kind

  def create
    Like.find_or_create_by!(user: current_user, tweet: @tweet, kind: @kind)

    if @tweet.user_id != current_user.id
      Notification.create!(user: @tweet.user, actor: current_user, kind: @kind,
                           tweet: @tweet,
                           body: "@#{current_user.username} #{@kind == Like::FAVOURITE ? 'favorited' : 'liked'} your tweet")
    end

    respond_to do |format|
      format.html { redirect_back fallback_location: tweet_path(@tweet) }
      format.json { render json: state_json }
    end
  end

  def destroy
    current_user.likes.where(tweet_id: @tweet.id, kind: @kind).delete_all

    respond_to do |format|
      format.html { redirect_back fallback_location: tweet_path(@tweet) }
      format.json { render json: state_json }
    end
  end

  private

  # The star and the heart share this controller; the route decides which
  # reaction is being toggled.
  def set_kind
    @kind = params[:kind] == "favourite" ? Like::FAVOURITE : Like::LIKE
  end

  # Toggles are driven from the page without a reload, so the response carries
  # everything the buttons need to repaint. Both reactions are reported so a
  # single request keeps the whole row in step.
  def state_json
    {
      id: @tweet.id,
      kind: @kind,
      liked: @tweet.liked_by?(current_user),
      like_count: @tweet.like_count,
      like_count_label: helpers.count_label(@tweet.like_count),
      favourited: @tweet.favourited_by?(current_user),
      favourite_count: @tweet.favourite_count,
      favourite_count_label: helpers.count_label(@tweet.favourite_count),
      retweeted: @tweet.retweeted_by?(current_user),
      retweet_count: @tweet.retweet_count,
      retweet_count_label: helpers.count_label(@tweet.retweet_count),
      reply_count: @tweet.reply_count,
      reply_count_label: helpers.count_label(@tweet.reply_count)
    }
  end

  def load_tweet
    @tweet = Tweet.visible.find_by(id: params[:id])
    return if @tweet

    render_not_found
  end
end