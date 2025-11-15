class SessionsController < ApplicationController
  # Skip authentication checks for login page
  skip_before_action :require_login, only: [ :new, :create ]

  def new
    # Redirect if already logged in
    redirect_to root_path if logged_in?
  end

  def create
    user = User.find_by(username: params[:username])

    if user&.authenticate(params[:password])
      session[:user_id] = user.id
      redirect_to root_path, notice: "Welcome back, #{user.username}!"
    else
      # Generic error message - don't reveal if username exists
      flash.now[:alert] = "Invalid username or password"
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    session[:user_id] = nil
    redirect_to root_path, notice: "You have been logged out"
  end
end
