class BookmarksController < ApplicationController
  before_action :require_login!

  # The saved posts of the signed-in account, newest save first. Only the
  # owner's own bookmarks are ever read, so the scope is pinned to
  # `current_user` and no id from the request can widen it.
  def index
    @tweets = Tweet.visible
                  .readable_by(current_user)
                  .where(id: current_user.bookmarks.select(:tweet_id))
                  .includes(:user, retweet_of: :user, quote_of: :user, parent: :user)
                  .recent
                  .limit(100)
  end

  # Toggling, so the same endpoint both saves and unsaves. The button
  # advertises which it will do, and the response carries the new state so the
  # page can repaint in place without a reload.
  def create
    tweet = Tweet.visible.readable_by(current_user).find_by(id: params[:tweet_id])
    return render_bookmark_error("That post is not available.") if tweet.nil?

    current_user.bookmarks.find_or_create_by!(tweet: tweet)
    audit!("bookmark.create", target: "tweet:#{tweet.id}", detail: "saved a post")

    respond_to do |format|
      format.html { redirect_back fallback_location: tweet_path(tweet), notice: "Post saved." }
      format.json { render json: { id: tweet.id, bookmarked: true } }
    end
  end

  def destroy
    tweet = Tweet.find_by(id: params[:tweet_id])
    return render_bookmark_error("That post is not available.") if tweet.nil?

    current_user.bookmarks.where(tweet_id: tweet.id).delete_all

    respond_to do |format|
      format.html { redirect_back fallback_location: tweet_path(tweet), notice: "Post removed from your saved posts." }
      format.json { render json: { id: tweet.id, bookmarked: false } }
    end
  end

  # Removes every saved post. Not an admin power: the scope is the signed-in
  # account's own bookmarks only.
  def clear
    removed = current_user.bookmarks.count
    current_user.bookmarks.delete_all

    audit!("bookmark.clear", target: "user:#{current_user.id}", detail: "removed #{removed} saved posts")
    redirect_to bookmarks_path, notice: "Removed #{removed} saved #{'post'.pluralize(removed)}."
  end

  private

  def render_bookmark_error(message)
    respond_to do |format|
      format.html { redirect_back fallback_location: home_path, alert: message }
      format.json { render json: { error: message }, status: :not_found }
    end
  end
end