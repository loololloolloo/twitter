module Admin
  # Member lists, read across the whole site. A list is otherwise only visible
  # to its owner, so an operator cannot see that a public list has been renamed
  # to something abusive, or that one account is curating a very large set.
  #
  # Closing a list is the one write: it flips the visibility off rather than
  # deleting, so the members and the audit entry survive.
  class ListsController < AdminController
    def index
      return refuse unless can?("lists.view")

      @search = params[:q].to_s.strip
      @visibility = params[:visibility].to_s

      scope = List.includes(:user)
      scope = scope.where(is_private: false) if @visibility == "public"
      scope = scope.where(is_private: true)  if @visibility == "private"

      if @search.present?
        scope = scope.joins(:user).where(
          "lists.name LIKE :term OR lists.description LIKE :term OR users.username LIKE :term",
          term: "%#{@search}%"
        )
      end

      @lists = scope.order(created_at: :desc, id: :desc).limit(200)
      @member_counts = ListMembership.group(:list_id).count
    end

    def update
      return refuse unless can?("lists.view")

      list = List.find_by(id: params[:id])
      return redirect_to(admin_lists_path, alert: "List not found.") if list.nil?

      list.update!(is_private: params[:is_private].to_s == "1")
      audit!("lists.visibility", target: "list:#{list.id}",
                                detail: "#{list.is_private ? 'made private' : 'made public'}")

      redirect_to admin_lists_path, notice: "\"#{list.name}\" is now #{list.is_private ? 'private' : 'public'}."
    end

    private

    def refuse
      redirect_to admin_root_path, alert: "You do not have the lists.view permission."
    end
  end
end
