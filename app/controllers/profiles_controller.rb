class ProfilesController < ApplicationController
  before_action :require_login!
  before_action :load_profile

  def show
    @active = params[:tab].presence_in(%w[tweets favorites media]) || "tweets"

    # A permanently banned account gets a notice instead of a profile: none of
    # its content, counts or tabs are loaded, and the profile is reported as not
    # being the viewer's own so the edit/manage branches are not rendered.
    if @user.permanently_banned?
      @is_me = false
      @is_following = false
      return
    end

    @tweet_count = @user.tweet_count
    @following_count = @user.following_count
    @follower_count = @user.follower_count
    @favorites_count = @user.likes.favourites.count
    @is_me = @user.id == current_user.id
    @is_following = current_user.following.exists?(id: @user.id)

    # The profile is three columns wide, so the left rail carries a strip of the
    # account's own media and the right rail carries suggestions. Both are
    # loaded here rather than lazily so the page arrives complete.
    @photo_strip = Tweet.visible.where(user_id: @user.id)
                        .where.not(media_path: [ nil, "" ])
                        .recent.limit(3)

    @suggestions = User.visible
                       .where.not(id: [ current_user.id, @user.id ])
                       .order(Arel.sql("RANDOM()"))
                       .limit(3)

    if @active == "media"
      @media = Tweet.visible.where(user_id: @user.id)
                     .where.not(media_path: [ nil, "" ])
                     .recent.limit(60)
    elsif @active == "favorites"
      @tweets = Tweet.visible
                     .where(id: @user.likes.favourites.select(:tweet_id))
                     .includes(:user, retweet_of: :user)
                     .recent.limit(60)
    else
      @tweets = Tweet.visible.where(user_id: @user.id)
                     .includes(:user, retweet_of: :user)
                     .recent.limit(60)
    end
  end

  def following
    return redirect_to(profile_path(@user.username)) if @user.permanently_banned?

    @active = "following"
    @people = @user.following.order(:username).limit(200)
    render :connections
  end

  def followers
    return redirect_to(profile_path(@user.username)) if @user.permanently_banned?

    @active = "followers"
    @people = @user.followers.order(:username).limit(200)
    # Accounts granted bonus followers by an administrator have a higher
    # advertised total than the number of real follower rows, so the gap is
    # reported instead of silently hidden.
    @bonus_followers = @user.bonus_followers.to_i
    render :connections
  end

  private

  def load_profile
    @user = User.find_by("username = ? COLLATE NOCASE", params[:username])
    return if @user

    render plain: "Not found", status: :not_found
  end
end