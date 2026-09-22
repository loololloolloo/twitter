module Admin
  # Duplicate-account clusters. A queue of the account groups that share signup
  # signals - one mailbox shape, one signup window, one handle shape - so an
  # operator can see who arrived together rather than meeting each account a
  # page at a time.
  #
  # The screen is a hint, not a verdict. Every signal it shows is evidence an
  # operator still has to weigh, and nothing here is automatic, so the whole
  # surface is read-only and needs no confirmation.
  class SockpuppetsController < AdminController
    def index
      return refuse unless can?("relations.view")

      @clusters = SockpuppetCluster.new(User.all).clusters
    end

    private

    def refuse
      redirect_to admin_root_path, alert: "You do not have the relations.view permission."
    end
  end
end
