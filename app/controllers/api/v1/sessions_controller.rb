module Api
  module V1
    class SessionsController < BaseController
      skip_before_action :authenticate_user, only: [ :create ]

      def create
        user = User.find_by(username: params[:username])

        if user&.authenticate(params[:password])
          # Generate JWT token
          token = JwtService.encode({ user_id: user.id })

          # Set cookie for backward compatibility (session fallback)
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
        cookies.delete(:jwt_token)
        session[:user_id] = nil
        render json: { message: "Logged out successfully" }
      end

      def refresh
        if current_user
          token = JwtService.encode({ user_id: current_user.id })
          cookies[:jwt_token] = {
            value: token,
            httponly: true,
            secure: Rails.env.production?,
            same_site: :lax
          }
          render json: { token: token }
        else
          render json: { error: "Unauthorized" }, status: :unauthorized
        end
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
