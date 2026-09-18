# Reporting from the client, as opposed to the moderation queue that reads the
# result. A signed-in account reports a post or an account; a report lands in
# the same table the admin queue already reads, so nothing downstream changes.
#
# The reporter is always the signed-in account and is taken from the session,
# never from the request: a report that could name somebody else as its author
# would let one account put words in another's mouth in the moderation queue.
class ReportsController < ApplicationController
  before_action :require_login!

  # The categories offered depend on what is being reported. A post can be
  # reported for spam or abuse; an account additionally for impersonation, and
  # either for private information.
  TWEET_CATEGORIES = %w[spam abuse hate private_info self_harm other].freeze
  ACCOUNT_CATEGORIES = %w[spam abuse hate impersonation private_info self_harm other].freeze

  def new
    @subject = load_subject
    return if performed?

    @categories = @subject.is_a?(Tweet) ? TWEET_CATEGORIES : ACCOUNT_CATEGORIES
  end

  def create
    @subject = load_subject
    return if performed?

    category = params[:category].to_s
    allowed = @subject.is_a?(Tweet) ? TWEET_CATEGORIES : ACCOUNT_CATEGORIES

    unless allowed.include?(category)
      @categories = allowed
      flash.now[:error] = "Choose a reason for the report."
      return render :new, status: :unprocessable_entity
    end

    report = Report.create!(
      user: @subject.is_a?(Tweet) ? @subject.user : @subject,
      reporter: current_user,
      tweet: @subject.is_a?(Tweet) ? @subject : nil,
      category: category,
      detail: params[:detail].to_s.strip.first(500)
    )

    audit!("report.create", target: "report:#{report.id}", detail: "reported #{category}")

    redirect_back fallback_location: home_path,
                  notice: "Thanks. Your report has been sent to the review team."
  end

  private

  # The thing being reported, named by one of two parameters. Only one shape is
  # ever loaded, and an unknown id or username is a 404 rather than a redirect,
  # so a form cannot be reached for something that does not exist.
  def load_subject
    if params[:tweet_id].present?
      tweet = Tweet.visible.find_by(id: params[:tweet_id])
      return tweet || render_not_found
    end

    if params[:username].present?
      account = User.find_by("username = ? COLLATE NOCASE", params[:username])
      return account || render_not_found
    end

    render_not_found
  end
end