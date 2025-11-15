class UsersController < ApplicationController
  before_action :set_user, only: [ :show, :edit, :update, :destroy ]
  before_action :require_owner, only: [ :edit, :update, :destroy ]
  # Allow public access to show and signup without login
  skip_before_action :require_login, only: [ :show, :new, :create ]

  def new
    # Redirect if already logged in
    redirect_to root_path if logged_in?
    @user = User.new
  end

  def create
    @user = User.new(user_params_for_signup)

    if @user.save
      session[:user_id] = @user.id
      redirect_to root_path, notice: "Welcome to Microblog, #{@user.username}!"
    else
      flash.now[:alert] = @user.errors.full_messages.join(", ")
      render :new, status: :unprocessable_entity
    end
  end

  def show
    # Cache user profile data (1 hour TTL for user, 5 minutes for posts)
    # User model is cached separately from posts to allow independent invalidation
    @user = Rails.cache.fetch("user:#{params[:id]}", expires_in: 1.hour) do
      User.find(params[:id])
    end

    # Cache user posts with cursor-based key
    cache_key = "user_posts:#{params[:id]}:#{params[:cursor]}"
    cached_posts = Rails.cache.read(cache_key)

    if cached_posts
      @posts, @next_cursor, @has_next = cached_posts
    else
      @posts, @next_cursor, @has_next = cursor_paginate(
        @user.posts.top_level.timeline,
        per_page: 20
      )
      Rails.cache.write(cache_key, [ @posts, @next_cursor, @has_next ], expires_in: 5.minutes)
    end

    @followers_count = @user.followers_count
    @following_count = @user.following_count
  end

  def edit
    # @user already set by set_user before_action
  end

  def update
    if @user.update(user_params)
      # Invalidate user cache when profile is updated
      Rails.cache.delete("user:#{@user.id}")
      redirect_to @user, notice: "Settings updated successfully!"
    else
      flash[:alert] = @user.errors.full_messages.join(", ")
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    # @user already set by set_user before_action

    # Invalidate user cache (specific key, not pattern matching)
    Rails.cache.delete("user:#{@user.id}")

    # Note: user_posts cache invalidation removed - cache will expire via TTL
    # With fan-out on write, feed entries are deleted when user is destroyed,
    # so feed queries will be correct without cache invalidation

    # Verify password if authentication is enabled (for later)
    # For now, just delete the account
    @user.destroy
    session[:user_id] = nil
    redirect_to root_path, notice: "Your account has been deleted."
  end

  private

  def set_user
    # Don't cache here - caching is handled in show action
    # This allows edit/update/destroy to work with fresh data
    @user = User.find(params[:id])
  end

  def user_params
    permitted = params.require(:user).permit(:description, :password, :password_confirmation)
    # Only update password if provided
    permitted.delete(:password) if permitted[:password].blank?
    permitted.delete(:password_confirmation) if permitted[:password_confirmation].blank?
    permitted
  end

  def user_params_for_signup
    params.require(:user).permit(:username, :password, :password_confirmation)
  end


  def require_owner
    unless current_user == @user
      redirect_to root_path, alert: "You can only edit your own account."
    end
  end
end
