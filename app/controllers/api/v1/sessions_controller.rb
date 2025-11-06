module Api
  module V1
    class SessionsController < BaseController
      skip_before_action :authenticate_user, only: [:create]

      def create
        user = User.find_by(username: params[:username])

        if user&.authenticate(params[:password])
          # For now, use session (same as monolith) for parallel running
          # Later, we'll add JWT token generation here
          session[:user_id] = user.id

          render json: {
            user: user_json(user),
            message: "Login successful"
          }
        else
          render json: { error: "Invalid username or password" }, status: :unauthorized
        end
      end

      def show
        render json: { user: user_json(current_user) }
      end

      def destroy
        session[:user_id] = nil
        render json: { message: "Logged out successfully" }
      end

      private

      def user_json(user)
        {
          id: user.id,
          username: user.username,
          description: user.description,
          followers_count: user.followers_count,
          following_count: user.following_count,
          posts_count: user.posts_count
        }
      end
    end
  end
end

