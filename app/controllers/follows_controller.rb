class FollowsController < ApplicationController
  before_action :require_login
  before_action :set_followed_user, only: [:create, :destroy]

  def create
    if current_user.follow(@followed_user)
      redirect_back(fallback_location: user_path(@followed_user), notice: "You are now following #{@followed_user.username}")
    else
      redirect_back(fallback_location: user_path(@followed_user), alert: "Unable to follow user. #{current_user.errors.full_messages.join(', ')}")
    end
  end

  def destroy
    if current_user.unfollow(@followed_user)
      redirect_back(fallback_location: user_path(@followed_user), notice: "You have unfollowed #{@followed_user.username}")
    else
      redirect_back(fallback_location: user_path(@followed_user), alert: "Unable to unfollow user.")
    end
  end

  private

  def set_followed_user
    @followed_user = User.find(params[:user_id])
  end

  def require_login
    unless logged_in?
      redirect_to root_path, alert: 'You must be logged in to follow users.'
    end
  end
end

