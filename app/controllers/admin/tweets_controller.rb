module Admin
  class TweetsController < AdminController
    before_action :require_view_permission, only: [ :index ]
    before_action :require_delete_permission, only: [ :destroy ]

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
  end
end