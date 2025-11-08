module Api
  module V1
    class PostsController < BaseController
      skip_before_action :authenticate_user, only: [:index, :show]

      def index
        filter = params[:filter] || "timeline"
        per_page = 20
        post_filter = PostFilter.new(current_user)
        include_redacted = params[:include_redacted] == "true" && post_filter.include_redacted?

        if current_user
          case filter
          when "mine"
            posts_relation = current_user.posts.timeline
          when "following"
            user_id = Post.connection.quote(current_user.id)
            posts_relation = Post.joins(
              "INNER JOIN follows ON posts.author_id = follows.followed_id AND follows.follower_id = #{user_id}"
            ).timeline.distinct
          else
            # Cache feed posts with cursor-based key (5-minute TTL)
            # Include include_redacted in cache key to avoid cache conflicts
            cache_key = "user_feed:#{current_user.id}:#{params[:cursor]}:#{include_redacted}"
            cached_result = Rails.cache.read(cache_key)

            if cached_result
              posts, next_cursor, has_next = cached_result
              # Filter redacted posts unless admin
              posts = posts.reject { |p| p.redacted? } unless include_redacted
              render json: {
                posts: posts.map { |p| post_json(p) },
                pagination: {
                  cursor: next_cursor,
                  has_next: has_next
                }
              }
              return
            end

            posts_relation = current_user.feed_posts.timeline
          end
        else
          # Public posts (not authenticated)
          cache_key = "public_posts:#{params[:cursor]}"
          cached_result = Rails.cache.read(cache_key)

          if cached_result
            posts, next_cursor, has_next = cached_result
            # Filter redacted posts (silent redaction)
            posts = posts.reject { |p| p.redacted? }
          else
            posts_relation = Post.top_level.timeline
            posts, next_cursor, has_next = cursor_paginate(posts_relation, per_page: per_page)
            # Filter redacted posts before caching
            posts = posts.reject { |p| p.redacted? }
            Rails.cache.write(cache_key, [posts, next_cursor, has_next], expires_in: 1.minute)
          end

          render json: {
            posts: posts.map { |p| post_json(p) },
            pagination: {
              cursor: next_cursor,
              has_next: has_next
            }
          }
          return
        end

        # Filter redacted posts unless admin explicitly requests them (silent redaction)
        posts_relation = include_redacted ? posts_relation : posts_relation.not_redacted

        # Execute query and paginate
        posts, next_cursor, has_next = cursor_paginate(posts_relation, per_page: per_page)

        # Cache the paginated result for feed queries (if not already cached)
        if filter == "timeline" && current_user
          cache_key = "user_feed:#{current_user.id}:#{params[:cursor]}:#{include_redacted}"
          Rails.cache.write(cache_key, [posts, next_cursor, has_next], expires_in: 5.minutes)
        end

        render json: {
          posts: posts.map { |p| post_json(p) },
          pagination: {
            cursor: next_cursor,
            has_next: has_next
          }
        }
      end

      def show
        post = Post.find(params[:id])
        post_filter = PostFilter.new(current_user)
        include_redacted = params[:include_redacted] == "true" && post_filter.include_redacted?
        
        # Silent redaction: Return 404 for redacted posts unless admin
        unless include_redacted
          return head :not_found if post.redacted?
        end

        replies_cursor = params[:replies_cursor] || params[:cursor]
        # Filter redacted replies unless admin
        replies_relation = post_filter.filter_redacted(post.replies)
        replies, replies_next_cursor, replies_has_next = cursor_paginate(
          replies_relation.order(created_at: :asc),
          per_page: 20,
          cursor: replies_cursor,
          order: :asc
        )

        render json: {
          post: post_json(post),
          replies: replies.map { |r| post_json(r) },
          pagination: {
            cursor: replies_next_cursor,
            has_next: replies_has_next
          }
        }
      end

      def create
        post = Post.new(post_params)
        post.author = current_user

        if post.save
          render json: { post: post_json(post) }, status: :created
        else
          render json: { errors: post.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def report
        target_post = Post.find(params[:id])
        report_service = ReportService.new
        redaction_service = RedactionService.new
        audit_logger = AuditLogger.new

        # Create report
        report = report_service.create_report(target_post, current_user)

        # Log in audit trail
        audit_logger.log_report(target_post, current_user)

        # Check if threshold is met and auto-redact
        if redaction_service.auto_redact_if_threshold(target_post)
          audit_logger.log_redaction(target_post, reason: 'auto')
        end

        render json: { message: "Report submitted" }, status: :ok
      rescue ReportService::DuplicateReportError => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue ReportService::SelfReportError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def post_params
        params.require(:post).permit(:content, :parent_id)
      end

      def post_json(post)
        {
          id: post.id,
          content: post.content, # Content is nil if redacted (filtered out before this)
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

