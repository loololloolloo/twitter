class PagesController < ApplicationController
  PAGES = {
    "about"   => "About",
    "help"    => "Help",
    "tos"     => "Terms of Service",
    "privacy" => "Privacy Policy"
  }.freeze

  def show
    @slug = params[:page]
    return render(plain: "Not found", status: :not_found) unless PAGES.key?(@slug)

    @title = PAGES[@slug]
    render :show
  end
end