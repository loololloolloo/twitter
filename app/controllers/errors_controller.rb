class ErrorsController < ApplicationController
  def not_found
    render_error(404, "That page does not exist.")
  end

  def forbidden
    render_error(403, "You do not have permission to view this page.")
  end

  def unprocessable
    render_error(422, "That request could not be processed.")
  end

  def internal_error
    render_error(500, "Something went wrong on our side.")
  end

  private

  def render_error(code, message)
    @code = code
    @message = message
    @back_path = signed_in? ? home_path : login_path

    respond_to do |format|
      format.html { render :show, status: code }
      format.any  { render plain: "#{code} #{message}", status: code }
    end
  end
end