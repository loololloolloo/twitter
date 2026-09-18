class AccountsController < ApplicationController
  before_action :require_login!

  # Every account this browser has signed into, in the order they were added.
  # Kept in the session rather than in the database because it is a property of
  # this browser, not of the accounts: two people sharing a machine each keep
  # their own set.
  def self.account_ids(session)
    Array(session[:account_ids]).map(&:to_i).uniq
  end

  def self.remember(session, user)
    ids = account_ids(session)
    ids << user.id unless ids.include?(user.id)
    session[:account_ids] = ids
  end

  # There is no account list screen any more: switching accounts happens in the
  # sidebar popover, and the list itself lives on the settings page's data
  # section. This address only forwards, and it stays behind `require_login!`
  # so the forward never leaks the list to a signed-out visitor.
  def index
    redirect_to settings_path(panel: "data")
  end

  def update
    user = User.find_by(id: params[:id])

    unless user && self.class.account_ids(session).include?(user.id)
      return redirect_to home_path, alert: "That account is not connected to this browser."
    end

    if user.is_suspended?
      return redirect_to home_path, alert: "This account is suspended."
    end

    session[:user_id] = user.id
    user.update_column(:last_login_at, Time.current)
    audit!("user.switched", target: "user:#{user.id}", detail: "switched to @#{user.username}")

    redirect_to home_path, notice: "Signed in as @#{user.username}."
  end

  # Removing an account from the browser is what drops it from the list; signing
  # out of the active account leaves the rest connected. Removing the active one
  # lands on whichever remains, so the menu never points at an account that is no
  # longer connected.
  def destroy
    ids = self.class.account_ids(session) - [ params[:id].to_i ]
    session[:account_ids] = ids

    if current_user&.id == params[:id].to_i
      session.delete(:user_id)

      if ids.any?
        session[:user_id] = ids.first
        return redirect_to home_path, notice: "Switched accounts."
      end

      return redirect_to login_path, notice: "Signed out."
    end

    redirect_to home_path, notice: "Account removed from this browser."
  end
end
