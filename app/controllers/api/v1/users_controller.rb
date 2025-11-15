module Api
  module V1
    class UsersController < BaseController
      skip_before_action :authenticate_user, only: [ :show, :create ]

      def show
        user = User.find(params[:id])
        post_filter = PostFilter.new(current_user)
        include_redacted = params[:include_redacted] == "true" && post_filter.include_redacted?

        # Get user posts, filtering redacted posts unless admin
        posts_relation = user.posts.top_level.timeline
        posts_relation = include_redacted ? posts_relation : posts_relation.not_redacted

        # Paginate posts
        posts, next_cursor, has_next = cursor_paginate(posts_relation, per_page: 20)

        # Check if current user is following this user
        is_following = current_user&.following?(user) || false

        render json: {
          user: user_json(user, is_following: is_following),
          posts: posts.map { |p| post_json(p) },
          pagination: {
            cursor: next_cursor,
            has_next: has_next
          }
        }
      end

      def create
        user = User.new(user_params_for_signup)

        if user.save
          # Generate JWT token
          token = JwtService.encode({ user_id: user.id })

          # Set cookie for backward compatibility
          cookies[:jwt_token] = {
            value: token,
            httponly: true,
            secure: Rails.env.production?,
            same_site: :lax
          }

          # Also set session for backward compatibility with monolith
          session[:user_id] = user.id

          render json: {
            user: user_json(user),
            token: token,
            message: "Account created successfully"
          }, status: :created
        else
          render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        user = User.find(params[:id])

        # Check ownership
        unless current_user == user
          return render json: { error: "You can only update your own profile" }, status: :forbidden
        end

        if user.update(user_params)
          # Invalidate user cache when profile is updated
          Rails.cache.delete("user:#{user.id}")
          render json: { user: user_json(user) }
        else
          render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        user = User.find(params[:id])

        # Check ownership
        unless current_user == user
          return render json: { error: "You can only delete your own account" }, status: :forbidden
        end

        # Invalidate user cache
        Rails.cache.delete("user:#{user.id}")

        user.destroy
        cookies.delete(:jwt_token)
        session[:user_id] = nil

        render json: { message: "Account deleted successfully" }
      end

      private

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

      def user_json(user, is_following: nil)
        {
          id: user.id,
          username: user.username,
          description: user.description,
          followers_count: user.followers_count,
          following_count: user.following_count,
          posts_count: user.posts_count,
          is_following: is_following
        }.compact
      end

      def post_json(post)
        {
          id: post.id,
          content: post.content,
          redacted: post.redacted?,
          author: {
            id: post.author_id,
            username: post.author_name
          },
          created_at: post.created_at.iso8601,
          parent_id: post.parent_id,
          replies_count: post.replies.count
        }
      end
    end
  end
end
