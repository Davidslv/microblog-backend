class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # Temporary helper for development - can manually set session[:user_id] in console
  # Authentication will be added later
  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  def logged_in?
    current_user.present?
  end

  # Temporary dev method - remove before production!
  def dev_login
    session[:user_id] = params[:user_id]
    redirect_to root_path, notice: "Logged in as user #{params[:user_id]} (dev mode)"
  end

  helper_method :current_user, :logged_in?
end
