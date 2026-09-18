module Admin
  class TweetsController < AdminController
    before_action :require_view_permission, only: [ :index ]
    before_action :require_delete_permission, only: [ :destroy ]
    before_action :require_pin_permission, only: [ :pin, :unpin ]

    def index
      @search = params[:q].to_s.strip
      @include_deleted = params[:deleted] == "1"

      scope = Tweet.includes(:user).recent
      scope = scope.where(is_deleted: true) if @include_deleted

      if @search.present?
        scope = scope.where("body LIKE ?", "%#{@search}%")
      end

      @tweets = scope.limit(200)
    end

    # Pinning is per author: only one post on a profile can be pinned, so
    # pinning one clears whichever was pinned before.
    def pin
      tweet = Tweet.find_by(id: params[:id])
      return redirect_to(admin_tweets_path, alert: "Tweet not found.") if tweet.nil?
      return redirect_to(admin_tweets_path, alert: "Deleted tweets cannot be pinned.") if tweet.is_deleted

      Tweet.where(user_id: tweet.user_id).where.not(pinned_at: nil).update_all(pinned_at: nil)
      tweet.update!(pinned_at: Time.current)
      audit!("tweets.pin", target: "tweet:#{tweet.id}", detail: "pinned by @#{tweet.user.username}")

      redirect_to admin_tweets_path, notice: "Tweet pinned to @#{tweet.user.username}'s profile."
    end

    def unpin
      tweet = Tweet.find_by(id: params[:id])
      return redirect_to(admin_tweets_path, alert: "Tweet not found.") if tweet.nil?

      tweet.update!(pinned_at: nil)
      audit!("tweets.pin", target: "tweet:#{tweet.id}", detail: "unpinned")

      redirect_to admin_tweets_path, notice: "Tweet unpinned."
    end

    # Soft delete: the row stays so the audit trail and any replies keep
    # pointing at something, but it disappears from every timeline.
    def destroy
      tweet = Tweet.find_by(id: params[:id])

      if tweet.nil?
        return redirect_to(admin_tweets_path, alert: "Tweet not found.")
      end

      tweet.update!(is_deleted: true)
      audit!("tweets.delete", target: "tweet:#{tweet.id}", detail: "soft deleted")
      redirect_to admin_tweets_path, notice: "Tweet deleted."
    end

    private

    def require_view_permission
      require_permission!("tweets.view")
    end

    def require_delete_permission
      require_permission!("tweets.delete")
    end

    def require_pin_permission
      require_permission!("tweets.pin")
    end
  end
end