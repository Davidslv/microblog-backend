module Api
  module V1
    class UsersController < BaseController
      skip_before_action :authenticate_user, only: [:show, :create]

      def show
        user = User.find(params[:id])
        posts, next_cursor, has_next = cursor_paginate(
          user.posts.top_level.timeline,
          per_page: 20
        )

        render json: {
          user: user_json(user),
          posts: posts.map { |p| post_json(p) },
          pagination: {
            cursor: next_cursor,
            has_next: has_next
          }
        }
      end

      def create
        user = User.new(user_params)

        if user.save
          # Use session for now (parallel with monolith)
          session[:user_id] = user.id
          render json: { user: user_json(user) }, status: :created
        else
          render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        # Check ownership
        unless current_user.id == params[:id].to_i
          render json: { error: "You can only update your own profile" }, status: :forbidden
          return
        end

        if current_user.update(user_params)
          # Invalidate cache
          Rails.cache.delete("user:#{current_user.id}")
          render json: { user: user_json(current_user) }
        else
          render json: { errors: current_user.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        # Check ownership
        unless current_user.id == params[:id].to_i
          render json: { error: "You can only delete your own account" }, status: :forbidden
          return
        end

        Rails.cache.delete("user:#{current_user.id}")
        current_user.destroy
        session[:user_id] = nil
        render json: { message: "Account deleted successfully" }
      end

      private

      def user_params
        if params[:action] == 'create'
          params.require(:user).permit(:username, :password, :password_confirmation)
        else
          permitted = params.require(:user).permit(:description, :password, :password_confirmation)
          # Only update password if provided
          permitted.delete(:password) if permitted[:password].blank?
          permitted.delete(:password_confirmation) if permitted[:password_confirmation].blank?
          permitted
        end
      end

      def user_json(user)
        {
          id: user.id,
          username: user.username,
          description: user.description,
          followers_count: user.followers_count,
          following_count: user.following_count,
          posts_count: user.posts_count,
          created_at: user.created_at.iso8601
        }
      end

      def post_json(post)
        {
          id: post.id,
          content: post.content,
          created_at: post.created_at.iso8601
        }
      end
    end
  end
end

