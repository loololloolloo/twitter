class RegistrationsController < ApplicationController
  def new
    redirect_to home_path if signed_in?

    @signups_closed = !SiteSetting.registration_open?
  end

  def create
    unless SiteSetting.registration_open?
      flash.now[:error] = "Signups are currently closed."
      return render :new, status: :forbidden
    end

    # The very first account created owns the instance and holds every
    # permission; everyone after that starts as a regular member.
    is_first = User.none?
    role = Role.find_by!(name: is_first ? Role::OWNER : "user")

    @user = User.new(
      username: params[:username].to_s.strip,
      display_name: params[:display_name].presence&.strip || params[:username].to_s.strip,
      email: params[:email].to_s.strip,
      role: role
    )
    @user.password = params[:password]

    if params[:password].to_s != params[:password_confirm].to_s
      @user.errors.add(:password_hash, "Passwords do not match")
      return render :new, status: :unprocessable_entity
    end

    if params[:password].to_s.length < 8
      @user.errors.add(:password_hash, "Password must be at least 8 characters")
      return render :new, status: :unprocessable_entity
    end

    if @user.save
      AuditLog.record(
        actor: @user,
        action: "user.signup",
        target: "user:#{@user.id}",
        detail: "@#{@user.username} registered as #{role.name}" \
                "#{' (first account - owner privileges granted)' if is_first}"
      )

      session[:user_id] = @user.id
      AccountsController.remember(session, @user)
      if is_first
        flash[:success] = "Welcome, owner. You are the first account, so this instance is " \
                          "yours - you have every administrative permission."
      else
        flash[:success] = "Welcome, @#{@user.username}."
      end
      redirect_to home_path
    else
      render :new, status: :unprocessable_entity
    end
  end
end