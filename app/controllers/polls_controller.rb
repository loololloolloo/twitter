class PollsController < ApplicationController
  before_action :require_login!
  before_action :load_option

  def vote
    poll = @option.poll

    # A closed poll keeps showing its result but accepts nothing more.
    if poll.closed?
      return respond_with(alert: "This poll has ended.")
    end

    # Changing a vote is not allowed: the first choice stands, which is the
    # rule the client enforced and the unique index also guarantees.
    if poll.voted_by?(current_user)
      return respond_with(alert: "You have already voted in this poll.")
    end

    vote = PollVote.new(poll: poll, poll_option: @option, user: current_user)

    if vote.save
      respond_with(notice: "Your vote was counted.")
    else
      # Reaching here means the unique index rejected a concurrent second vote,
      # so the reader's own earlier vote is what stands.
      respond_with(alert: "You have already voted in this poll.")
    end
  rescue ActiveRecord::RecordNotUnique
    respond_with(alert: "You have already voted in this poll.")
  end

  private

  # A vote names a choice, not a post, so the choice is what the route carries.
  # It is loaded through the post's readable scope so a poll on a post the
  # reader may not see cannot be voted in by guessing an option id.
  def load_option
    @option = PollOption.joins(:poll).where(polls: { tweet_id: Tweet.visible.readable_by(current_user).select(:id) })
                        .find_by(id: params[:id])
    return if @option

    render_not_found
  end

  def respond_with(notice: nil, alert: nil)
    respond_to do |format|
      format.html { redirect_back fallback_location: tweet_path(@option.poll.tweet), notice: notice, alert: alert }
      format.json { render json: poll_json.merge(notice: notice, alert: alert) }
    end
  end

  # The whole poll is returned because a vote changes every share, not just the
  # chosen one; the client repaints the block from this.
  def poll_json
    poll = @option.poll
    {
      id: poll.id,
      tweet_id: poll.tweet_id,
      closed: poll.closed?,
      total_votes: poll.total_votes,
      voted: poll.voted_by?(current_user),
      winning_option_id: poll.winning_option_id,
      options: poll.poll_options.map do |option|
        { id: option.id, label: option.label, votes: poll.poll_votes.where(poll_option_id: option.id).count,
          share: poll.shares[option.id] }
      end
    }
  end
end