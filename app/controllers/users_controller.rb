class UsersController < ApplicationController
  before_action :set_user, only: [:show, :edit, :update, :destroy]
  before_action :require_login, only: [:edit, :update, :destroy]
  before_action :require_owner, only: [:edit, :update, :destroy]

  def show
    # Paginate user posts using cursor-based pagination
    @posts, @next_cursor, @has_next = cursor_paginate(
      @user.posts.top_level.timeline,
      per_page: 20
    )
    # Use counter cache instead of counting (100x faster)
    @followers_count = @user.followers_count
    @following_count = @user.following_count
  end

  def edit
    # @user already set by set_user before_action
  end

  def update

    if @user.update(user_params)
      redirect_to @user, notice: 'Settings updated successfully!'
    else
      flash[:alert] = @user.errors.full_messages.join(', ')
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    # @user already set by set_user before_action

    # Verify password if authentication is enabled (for later)
    # For now, just delete the account
    @user.destroy
    session[:user_id] = nil
    redirect_to root_path, notice: 'Your account has been deleted.'
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    permitted = params.require(:user).permit(:description, :password, :password_confirmation)
    # Only update password if provided
    permitted.delete(:password) if permitted[:password].blank?
    permitted.delete(:password_confirmation) if permitted[:password_confirmation].blank?
    permitted
  end

  def require_login
    unless logged_in?
      redirect_to root_path, alert: 'You must be logged in to perform that action.'
    end
  end

  def require_owner
    unless current_user == @user
      redirect_to root_path, alert: 'You can only edit your own account.'
    end
  end
end

