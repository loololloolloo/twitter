class ProfilesController < ApplicationController
  before_action :require_login!
  before_action :load_profile

  # The 2019 tabs are Tweets, Tweets & replies, Media and Likes. `favorites`
  # is kept as an accepted alias because older links and tests still use it.
  TABS = %w[tweets replies media likes favorites scheduled].freeze

  def show
    @active = params[:tab].presence_in(TABS) || "tweets"
    @active = "likes" if @active == "favorites"

    # A permanently banned account gets a notice instead of a profile: none of
    # its content, counts or tabs are loaded, and the profile is reported as not
    # being the viewer's own so the edit/manage branches are not rendered.
    if @user.permanently_banned?
      @is_me = false
      @is_following = false
      return
    end

    # A block hides both accounts from each other entirely. The profile still
    # renders, but as a notice rather than as content: the reader is told the
    # relationship exists without being shown anything about the account.
    @blocked = current_user.blocked_with?(@user)
    @muted = current_user.muting?(@user)

    if @blocked
      @is_me = false
      @is_following = false
      return
    end

    # A protected account the viewer does not follow shows its header and
    # counts but none of its posts, which is what the 2019 client did.
    @locked = !@user.readable_by?(current_user)
    @request_pending = @user.pending_request_from?(current_user)

    @tweet_count = @user.tweet_count
    @following_count = @user.following_count
    @follower_count = @user.follower_count
    @favorites_count = @user.likes.favourites.count
    @is_me = @user.id == current_user.id
    @is_following = current_user.following.exists?(id: @user.id)
    # The 2019 header showed a "Follows you" chip beside the handle when the
    # account on screen follows the viewer. It answers "who is this" faster than
    # the bio, and only the viewer can see it, so it is derived per request
    # rather than cached on the profile.
    @follows_me = !@is_me && @user.following.exists?(id: current_user.id)

    # The scheduled list is the writer's own: it shows posts that are not out
    # yet, so anyone else asking for it falls back to the ordinary Tweets tab
    # rather than being told the list exists but is private.
    @active = "tweets" if @active == "scheduled" && !@is_me

    # A locked profile has nothing to show in the panels below, so the loads are
    # skipped rather than run and discarded.
    if @locked
      @tweets = []
      @photo_strip = []
      @suggestions = profile_suggestions
      return
    end

    # The profile is three columns wide, so the left rail carries a strip of the
    # account's own media and the right rail carries suggestions. Both are
    # loaded here rather than lazily so the page arrives complete.
    @photo_strip = Tweet.visible.readable_by(current_user).where(user_id: @user.id)
                        .with_media
                        .recent.limit(3)

    @suggestions = profile_suggestions

    if @active == "media"
      @media = Tweet.visible.readable_by(current_user).where(user_id: @user.id)
                     .with_media
                     .includes(:user, retweet_of: :user, quote_of: :user, parent: :user)
                     .recent.limit(60)
    elsif @active == "likes"
      @tweets = Tweet.visible.readable_by(current_user)
                     .where(id: @user.likes.favourites.select(:tweet_id))
                     .includes(:user, retweet_of: :user, quote_of: :user, parent: :user)
                     .recent.limit(60)
    elsif @active == "scheduled"
      # The writer's queue of posts whose moment has not arrived, earliest
      # first, because that is the order they will go out. Scoped by author so
      # it can only ever be the viewer's own list.
      @scheduled = current_user.tweets.where(is_deleted: false)
                            .scheduled.order(:scheduled_at).limit(60)
    elsif @active == "replies"
      # "Tweets & replies" is everything the account posted, replies included,
      # which is the unfiltered author scope.
      @tweets = Tweet.visible.readable_by(current_user).where(user_id: @user.id)
                     .includes(:user, retweet_of: :user, quote_of: :user, parent: :user)
                     .recent.limit(60)
    else
      # The default Tweets tab is the account's own posts without replies,
      # matching the 2019 profile, which hides replies unless asked for.
      @tweets = Tweet.visible.readable_by(current_user).where(user_id: @user.id, parent_id: nil)
                     .includes(:user, retweet_of: :user, quote_of: :user, parent: :user)
                     .recent.limit(60)

      # A pinned post sits at the top of this tab only, the way the 2019 client
      # showed it: it is not a second copy, it moves the existing entry up.
      @pinned = @tweets.find(&:pinned_at)
      @tweets = @tweets.reject { |tweet| tweet.id == @pinned&.id } if @pinned
    end
  end

  def following
    return redirect_to(profile_path(@user.username)) if @user.permanently_banned?
    return redirect_to(profile_path(@user.username)) if current_user.blocked_with?(@user)

    @active = "following"
    @people = @user.following.where.not(id: current_user.silenced_account_ids).order(:username).limit(200)
    render :connections
  end

  def followers
    return redirect_to(profile_path(@user.username)) if @user.permanently_banned?
    return redirect_to(profile_path(@user.username)) if current_user.blocked_with?(@user)

    @active = "followers"
    @people = User.where(id: @user.follower_ids)
                  .where.not(id: current_user.silenced_account_ids)
                  .order(:username).limit(200)
    # The advertised total can exceed the rows when an administrator granted a
    # bonus, which is reported rather than silently hidden.
    @bonus_followers = @user.bonus_followers.to_i
    render :connections
  end

  private

  # Who to follow, excluding the viewer, the account being viewed, anyone
  # already followed, and anyone the viewer has blocked or muted. Shared by both
  # branches of `show` so a locked profile and an open one propose the same way.
  def profile_suggestions
    excluded = [ current_user.id, @user.id ] + current_user.silenced_account_ids +
               current_user.following.pluck(:id)

    User.visible
        .where.not(id: excluded)
        .order(Arel.sql("RANDOM()"))
        .limit(3)
  end

  def load_profile
    @user = User.find_by("username = ? COLLATE NOCASE", params[:username])
    return if @user

    render_not_found
  end
end