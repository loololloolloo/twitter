class SessionsController < ApplicationController
  # An already-signed-in member can still open the form to add another account.
  # `?add=1` is what tells the two visits apart: a plain /login stays a redirect,
  # so a signed-in member is not dropped onto a login page they do not need.
  def new
    return if adding_account?

    redirect_to home_path if signed_in?
  end

  def create
    user = User.authenticate(params[:identifier], params[:password])

    if user.nil?
      flash.now[:error] = "Incorrect username or password."
      return render :new, status: :unprocessable_entity
    end

    if user.is_suspended?
      flash.now[:error] = "This account is suspended."
      return render :new, status: :forbidden
    end

    # Remembering appends rather than replaces, so an account added while
    # another is active joins the browser's list instead of clearing it.
    session[:user_id] = user.id
    AccountsController.remember(session, user)
    user.update_column(:last_login_at, Time.current)

    # Adding an account is an act of switching to it, so it lands on the home
    # feed as the new account rather than on a list screen.
    if adding_account?
      return redirect_to home_path, notice: "Added @#{user.username}."
    end

    # Signing in is an explicit act, so a ban screen is shown straight away
    # rather than only on the next request.
    if user.is_banned?
      redirect_to banned_path
    else
      redirect_to home_path
    end
  end

  # Signing out ends the session for the active account but keeps the other
  # accounts this browser has signed into - that list is a property of the
  # browser, and dropping it is what made the switcher collapse to one account.
  # Forgetting an account is a separate, explicit action on the account list.
  def destroy
    remembered = AccountsController.account_ids(session)

    session.delete(:user_id)
    reset_session

    session[:account_ids] = remembered if remembered.any?

    redirect_to login_path
  end

  private

  def adding_account?
    params[:add].present?
  end
end