module Api
  module V1
    module Admin
      class PostsController < BaseController
        before_action :ensure_admin

        def redact
          post = Post.find(params[:id])
          reason = params[:reason] || "manual"

          if post.redacted?
            return render json: { error: "Post is already redacted" }, status: :unprocessable_entity
          end

          redaction_service = RedactionService.new
          audit_logger = AuditLogger.new

          redaction_service.redact(post, reason: reason, admin: current_user)
          audit_logger.log_redaction(post, reason: reason, admin: current_user)

          render json: { message: "Post redacted", post: post_json(post) }, status: :ok
        end

        def unredact
          post = Post.find(params[:id])

          unless post.redacted?
            return render json: { error: "Post is not redacted" }, status: :unprocessable_entity
          end

          redaction_service = RedactionService.new
          audit_logger = AuditLogger.new

          redaction_service.unredact(post)
          audit_logger.log_unredaction(post, admin: current_user)

          render json: { message: "Post unredacted", post: post_json(post) }, status: :ok
        end

        def reports
          post = Post.find(params[:id])
          reports = post.reports.includes(:reporter).order(created_at: :desc)

          render json: {
            reports: reports.map { |r| report_json(r) }
          }, status: :ok
        end

        private

        def ensure_admin
          unless current_user&.admin?
            render json: { error: "Forbidden: Admin access required" }, status: :forbidden
          end
        end

        def post_json(post)
          {
            id: post.id,
            content: post.content,
            redacted: post.redacted?,
            redaction_reason: post.redaction_reason,
            author: {
              id: post.author_id,
              username: post.author_name
            },
            created_at: post.created_at.iso8601
          }
        end

        def report_json(report)
          {
            id: report.id,
            reporter: {
              id: report.reporter_id,
              username: report.reporter.username
            },
            created_at: report.created_at.iso8601
          }
        end
      end
    end
  end
end

