class PeopleController < ApplicationController
  def index
    require_login! || return

    @people = User.visible
                  .where.not(id: current_user.id)
                  .order(:username)
                  .limit(100)
  end
end