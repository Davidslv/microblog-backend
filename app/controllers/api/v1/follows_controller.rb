module Api
  module V1
    class FollowsController < BaseController
      def create
        user_to_follow = User.find(params[:user_id])

        if current_user.follow(user_to_follow)
          render json: { message: "Now following #{user_to_follow.username}" }
        else
          render json: { error: "Unable to follow user" }, status: :unprocessable_entity
        end
      end

      def destroy
        user_to_unfollow = User.find(params[:user_id])

        if current_user.unfollow(user_to_unfollow)
          render json: { message: "Unfollowed #{user_to_unfollow.username}" }
        else
          render json: { error: "Unable to unfollow user" }, status: :unprocessable_entity
        end
      end
    end
  end
end
