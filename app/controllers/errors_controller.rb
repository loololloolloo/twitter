class ErrorsController < ApplicationController
  def not_found
    render_not_found
  end

  def forbidden
    render_forbidden
  end

  def unprocessable
    render_error_page(422, "That request could not be processed.")
  end

  def internal_error
    render_error_page(500, "Something went wrong on our side.")
  end
end