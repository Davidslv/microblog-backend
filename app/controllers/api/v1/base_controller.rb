module Api
  module V1
    class BaseController < ActionController::API
      include ActionController::Cookies

      # Error handling
      rescue_from ActiveRecord::RecordNotFound, with: :not_found
      rescue_from ActiveRecord::RecordInvalid, with: :unprocessable_entity
      rescue_from ActionController::ParameterMissing, with: :bad_request

      # Authentication - supports both session (for parallel running) and JWT (for future)
      before_action :authenticate_user

      private

      def current_user
        @current_user ||= begin
          # Try JWT token first (primary authentication method)
          token = extract_jwt_token
          if token
            payload = JwtService.decode(token)
            return User.find_by(id: payload[:user_id]) if payload
          end

          # Fallback to session (for backward compatibility during migration)
          # This allows users logged in via monolith to access API
          if session[:user_id]
            return User.find_by(id: session[:user_id])
          end

          nil
        end
      end

      def authenticate_user
        unless current_user
          render json: { error: 'Unauthorized' }, status: :unauthorized
        end
      end

      def extract_jwt_token
        # Check Authorization header first
        auth_header = request.headers['Authorization']
        if auth_header && auth_header.start_with?('Bearer ')
          return auth_header.split(' ').last
        end

        # Fallback to cookie (for backward compatibility)
        cookies[:jwt_token]
      end

      def not_found(error)
        render json: { error: error.message }, status: :not_found
      end

      def unprocessable_entity(error)
        render json: { errors: error.record.errors.full_messages }, status: :unprocessable_entity
      end

      def bad_request(error)
        render json: { error: error.message }, status: :bad_request
      end

      # Helper method for cursor-based pagination (reused from ApplicationController)
      def cursor_paginate(relation, per_page: 20, cursor: nil, order: :desc)
        cursor_id = cursor || params[:cursor]
        cursor_id = cursor_id.to_i if cursor_id.present?

        if cursor_id.present? && cursor_id.is_a?(Integer) && cursor_id > 0
          if order == :asc
            relation = relation.where("posts.id > ?", cursor_id)
          else
            relation = relation.where("posts.id < ?", cursor_id)
          end
        end

        items = relation.limit(per_page + 1).to_a
        has_next = items.length > per_page
        items = items.take(per_page) if has_next
        next_cursor = items.last&.id

        [items, next_cursor, has_next]
      end
    end
  end
end

