module Admin
  # The toolbar's lookup surface. Where the Users list is browsed by name, this
  # is for when something concrete is already in hand - an id from a report, an
  # email from a message-ID, a handle from a screenshot - and the job is to
  # resolve it to the record it names.
  #
  # The lookup is deliberately exact rather than fuzzy: an operator pastes an
  # identifier and gets the row, which is the step real trust-and-safety tooling
  # leads with, because a display string can be forged and an id cannot.
  class LookupController < AdminController
    SOURCES = {
      "users"    => "Accounts",
      "tweets"   => "Posts",
      "lists"    => "Lists",
      "sessions" => "Sessions"
    }.freeze

    def index
      return refuse unless can?("lookup.run")

      @query = params[:q].to_s.strip
      @source = SOURCES.key?(params[:source]) ? params[:source] : "users"
      @result = nil
      @matches = []

      return if @query.blank?

      run_lookup
      audit!("lookup.run", target: @source, detail: "looked up #{@query.inspect}")
    end

    private

    # Resolve the term against the chosen source. An account term is matched on
    # id first, then username and email, so "@name", "name" and an address all
    # land on the same record.
    def run_lookup
      case @source
      when "users"    then lookup_users
      when "tweets"   then lookup_tweets
      when "lists"    then lookup_lists
      when "sessions" then lookup_sessions
      end
    end

    def lookup_users
      @result = User.includes(:role).find_by(id: @query) if @query.match?(/\A\d+\z/)
      @matches = User.includes(:role)
                     .where("username = :term OR email = :term", term: @query)
                     .limit(25)
                     .to_a
    end

    def lookup_tweets
      @result = Tweet.includes(:user).find_by(id: @query) if @query.match?(/\A\d+\z/)
      @matches = Tweet.includes(:user).where("body LIKE ?", "%#{@query}%").recent.limit(25).to_a
    end

    def lookup_lists
      @result = List.includes(:user).find_by(id: @query) if @query.match?(/\A\d+\z/)
      @matches = List.includes(:user).where("name LIKE ?", "%#{@query}%").limit(25).to_a
    end

    def lookup_sessions
      @result = Session.includes(:user).find_by(token: @query)
      @matches = Session.includes(:user).where("token LIKE ?", "%#{@query}%").limit(25).to_a
    end

    def refuse
      redirect_to admin_root_path, alert: "You do not have the lookup.run permission."
    end
  end
end
