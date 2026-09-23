class TweetsController < ApplicationController
  before_action :require_login!
  before_action :load_tweet, only: [ :show, :retweet, :destroy, :stats, :activity, :quotes ]

  def show
    # Replies the author has hidden stay visible to the author alone, greyed, so
    # the thread reads whole to the one person who hid them. Whether to keep a
    # hidden reply is decided by who is reading, not by who wrote the reply.
    replies = @tweet.replies.visible.includes(:user, parent: :user).order(:created_at)
    @hidden_count = replies.count(&:reply_hidden?)
    viewer_is_author = @tweet.user_id == current_user.id
    @replies = replies.reject { |reply| reply.reply_hidden? && !viewer_is_author }
    # The conversation above the focused post, oldest first. Each step is read
    # through the same `visible.readable_by` rule the focused post passed, so a
    # protected or banned parent the viewer may not open is not rendered here
    # just because the reply below it is readable; the chain stops at the first
    # ancestor that is withheld.
    @ancestors = []
    node = @tweet.parent
    while node && Tweet.visible.readable_by(current_user).exists?(id: node.id)
      @ancestors.unshift(node)
      node = node.parent
    end

    # The permalink is also where a quote of this post is composed, so the
    # composer's quote target is set here rather than on the timeline.
    @quote_of = @tweet if params[:quote].present?
  end

  # The per-post analytics screen. The 2019 client showed impressions and
  # engagement for the author's own posts only, so this is restricted to the
  # author (or an operator with the delete permission).
  def activity
    unless @tweet.user_id == current_user.id || can?("tweets.delete")
      return redirect_to tweet_path(@tweet), alert: "You can only see activity for your own posts."
    end

    @impressions = TweetView.where(tweet_id: @tweet.id).count
    # A view with dwell time recorded is one where the reader stayed, which is
    # the closest thing this schema has to the client's "detail expands" figure.
    @detail_impressions = TweetView.where(tweet_id: @tweet.id).where("dwell_seconds > 0").count
    @profile_visits = ProfileView.where(user_id: @tweet.user_id).count
    @engagement = @tweet.like_count + @tweet.favourite_count + @tweet.retweet_count + @tweet.reply_count
    @rate = @impressions.positive? ? (@engagement.to_f / @impressions * 100).round(1) : 0.0
  end

  # The posts that quote this one, which the permalink's "Quote Tweets" figure
  # opens. Read through the same `visible.readable_by` rule as every timeline,
  # so a quote by an account the viewer has blocked or silenced, or by a
  # permanently banned account, is not surfaced here even though the live count
  # on the permalink still includes it - the count answers "how many", this
  # screen answers "which ones, that you may read".
  def quotes
    @quotes = @tweet.quotes.visible
                     .readable_by(current_user)
                     .includes(:user, quote_of: :user)
                     .recent
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

    # A GIF arrives either as a chosen file or as a pasted link. The file goes
    # through the normal upload path; the link is resolved to an embeddable URL
    # first, and only stored once it resolves, so a post never points at a link
    # the renderer would have to fetch or guess at.
    gif_file = params[:gif_file]
    has_gif_file = gif_file.present? && gif_file.respond_to?(:original_filename) && gif_file.original_filename.present?
    media = gif_file if !has_media && has_gif_file
    has_media = has_media || has_gif_file

    gif_url = nil
    if params[:gif_url].present? && !has_media
      gif_url = GifLink.resolve(params[:gif_url])
      if gif_url.nil?
        redirect_back fallback_location: home_path, alert: "That GIF link could not be used."
        return
      end
    end

    quote_of_id = params[:quote_of_id].presence

    # A poll is built before the emptiness check so a poll-only post counts as
    # content. The builder returns nil for a half-filled poll, which then falls
    # back to the ordinary empty-post rule rather than saving a broken poll.
    poll = Poll.build_for(nil, options: params.dig(:poll, :options), duration: params.dig(:poll, :duration))

    if body.empty? && !has_media && gif_url.blank? && quote_of_id.blank? && poll.nil?
      redirect_back fallback_location: home_path, alert: "Your tweet was empty."
      return
    end

    if body.length > max_tweet_length
      redirect_back fallback_location: home_path,
                    alert: "Tweets must be #{max_tweet_length} characters or fewer."
      return
    end

    # A schedule is the 2019 composer's last control: the post is written now
    # and withheld until the chosen moment. It is refused unless it is in the
    # future, because a stamp in the past would publish instantly while telling
    # the writer the post was queued - a silent lie about where it went.
    scheduled_at = scheduled_time
    if params[:scheduled_at].present? && scheduled_at.nil?
      redirect_back fallback_location: home_path,
                    alert: "That schedule date could not be read. Use YYYY-MM-DD HH:MM."
      return
    end
    if scheduled_at && scheduled_at <= Time.current
      redirect_back fallback_location: home_path,
                    alert: "A scheduled tweet has to be at least a minute in the future."
      return
    end

    parent = params[:parent_id].present? ? Tweet.visible.find_by(id: params[:parent_id]) : nil

    # A quote names the post it attaches. It is loaded through the readable
    # scope so a quote cannot be used to embed a post from a blocked or
    # protected account the reader may not see.
    quoted = nil
    if quote_of_id.present?
      quoted = Tweet.visible.readable_by(current_user).find_by(id: quote_of_id)
      if quoted.nil?
        redirect_back fallback_location: home_path, alert: "That post is not available."
        return
      end
    end

    # The upload is validated before the tweet is written so a rejected file
    # cannot leave a row pointing at a path that was never stored.
    media_path = Uploads.store(media, current_user.id)

    if has_media && media_path.nil?
      redirect_back fallback_location: home_path,
                    alert: "That file type is not supported. Attach an image (PNG, JPG, GIF or WebP) or a video (MP4 or WebM)."
      return
    end

    tweet = Tweet.create!(
      user: current_user,
      body: body,
      parent: parent,
      quote_of: quoted,
      media_path: media_path,
      media_url: gif_url,
      alt_text: params[:alt_text].to_s.strip.first(1000).presence,
      scheduled_at: scheduled_at
    )

    # The poll is attached after the post exists, because it carries the post's
    # id. It was built before only to decide whether the post had any content.
    if poll
      poll.tweet = tweet
      poll.save!
    end

    # A scheduled post is not out yet, so nobody is told about it: a reply or a
    # quote that cannot be read would send the recipient to a post that is not
    # there, and an @mention would wake an account over a draft. The
    # notifications are the reward for publishing, so they wait for the moment.
    unless tweet.scheduled_pending?
      if parent && parent.user_id != current_user.id
        Notification.create!(user: parent.user, actor: current_user, kind: "reply",
                             tweet: tweet, body: body.first(120))
      end

      if quoted && quoted.user_id != current_user.id
        Notification.create!(user: quoted.user, actor: current_user, kind: "quote",
                             tweet: tweet, body: "@#{current_user.username} quoted your tweet")
      end

      MentionScanner.notify(tweet)
    end

    if tweet.scheduled_pending?
      redirect_to profile_path(current_user.username, tab: "scheduled"),
                  notice: "Your tweet is scheduled for #{tweet.scheduled_at.strftime('%b %-d, %Y at %-I:%M %p')}."
    elsif parent
      redirect_to tweet_path(parent)
    else
      redirect_back fallback_location: home_path
    end
  end

  # Hiding a reply is the parent author's decision. Only the author of the post
  # being replied to can hide the reply, which is the rule the client enforced.
  def hide_reply
    moderate_reply(hidden: true)
  end

  def unhide_reply
    moderate_reply(hidden: false)
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

  # Hiding and unhiding are one rule applied two ways, so they share a body.
  # The reply is loaded without the readable scope on purpose: the parent's
  # author is the one account allowed to act on a reply it may not otherwise
  # be able to see, and the ownership check below is the gate.
  def moderate_reply(hidden:)
    reply = Tweet.find_by(id: params[:id])

    if reply.nil? || reply.parent_id.nil?
      redirect_to(home_path, alert: "That reply is not available.") and return
    end

    unless reply.parent.user_id == current_user.id || can?("tweets.delete")
      redirect_to(tweet_path(reply.parent), alert: "Only the author of the original post can hide a reply.") and return
    end

    hidden ? reply.hide_reply! : reply.unhide_reply!
    audit!(hidden ? "tweet.hide_reply" : "tweet.unhide_reply",
           target: "tweet:#{reply.id}", detail: hidden ? "hid a reply" : "unhid a reply")

    redirect_to tweet_path(reply.parent), notice: hidden ? "Reply hidden." : "Reply unhidden."
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

  # The composer sends the schedule as one local "YYYY-MM-DD HH:MM" string, the
  # way the 2019 date picker did. A datetime-local control submits ISO-8601, so
  # both spellings are accepted and read in the server's zone; anything else is
  # nil, which the caller turns into a refusal rather than a silent no-op.
  def scheduled_time
    raw = params[:scheduled_at].to_s.strip
    return nil if raw.empty?

    # Only the two spellings the composer can send are read. A lenient parse is
    # dangerous here: "next tuesday" would quietly become midnight today, and a
    # schedule the writer never chose is worse than a plain refusal.
    return nil unless raw.match?(/\A\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}(:\d{2})?\z/)

    parsed =
      begin
        Time.zone.parse(raw.tr("T", " "))
      rescue ArgumentError
        nil
      end
    parsed&.change(sec: 0)
  end

  def load_tweet
    # Scoped through `readable_by` so every action that names a post by id -
    # the permalink, retweet, stats, activity - applies the same rule: a
    # protected account's post is not readable by a stranger, and a 404 is the
    # answer rather than a page that then has to hide its own contents.
    @tweet = Tweet.visible
                  .readable_by(current_user)
                  .includes(:user, retweet_of: :user, quote_of: :user, parent: :user)
                  .find_by(id: params[:id])
    return if @tweet

    render_not_found
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
      quote_count: tweet.quote_count,
      quote_count_label: helpers.count_label(tweet.quote_count),
      reply_count: tweet.reply_count,
      reply_count_label: helpers.count_label(tweet.reply_count)
    }
  end
end