require 'rails_helper'

RSpec.describe "Api::V1::Reports", type: :request do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:target_post) { create(:post, author: other_user) }
  let(:api_base) { "/api/v1" }
  
  def get_token
    post "#{api_base}/login", params: { username: user.username, password: "password123" }
    JSON.parse(response.body)["token"]
  end

  describe "POST /api/v1/posts/:post_id/report" do
    context "when authenticated" do
      let(:token) { get_token }

      it "creates a report" do
        expect {
          post "#{api_base}/posts/#{target_post.id}/report",
               headers: { "Authorization" => "Bearer #{token}" }
        }.to change { Report.count }.by(1)
      end

      it "returns success message" do
        post "#{api_base}/posts/#{target_post.id}/report",
             headers: { "Authorization" => "Bearer #{token}" }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["message"]).to eq("Report submitted")
      end

      it "creates report with correct post and reporter" do
        post "#{api_base}/posts/#{target_post.id}/report",
             headers: { "Authorization" => "Bearer #{token}" }

        report = Report.last
        expect(report.post).to eq(target_post)
        expect(report.reporter).to eq(user)
      end

      it "triggers auto-redaction when threshold is met" do
        # Create 4 existing reports
        create_list(:report, 4, post: target_post)

        post "#{api_base}/posts/#{target_post.id}/report",
             headers: { "Authorization" => "Bearer #{token}" }

        target_post.reload
        expect(target_post.redacted).to be true
        expect(target_post.redaction_reason).to eq("auto")
      end

      it "logs the report in audit trail" do
        expect {
          post "#{api_base}/posts/#{target_post.id}/report",
               headers: { "Authorization" => "Bearer #{token}" }
        }.to change { ModerationAuditLog.count }.by(1)

        log = ModerationAuditLog.last
        expect(log.action).to eq("report")
        expect(log.post).to eq(target_post)
        expect(log.user).to eq(user)
      end
    end

    context "when not authenticated" do
      it "returns unauthorized" do
        post "#{api_base}/posts/#{target_post.id}/report"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with duplicate report" do
      let(:token) { get_token }

      before do
        create(:report, post: target_post, reporter: user)
      end

      it "returns error" do
        post "#{api_base}/posts/#{target_post.id}/report",
             headers: { "Authorization" => "Bearer #{token}" }

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json["error"]).to include("already been reported")
      end

      it "does not create duplicate report" do
        expect {
          post "#{api_base}/posts/#{target_post.id}/report",
               headers: { "Authorization" => "Bearer #{token}" }
        }.not_to change { Report.count }
      end
    end

    context "with self-report" do
      let(:token) { get_token }
      let(:own_post) { create(:post, author: user) }

      it "returns error" do
        post "#{api_base}/posts/#{own_post.id}/report",
             headers: { "Authorization" => "Bearer #{token}" }

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json["error"]).to include("Cannot report your own post")
      end

      it "does not create report" do
        expect {
          post "#{api_base}/posts/#{own_post.id}/report",
               headers: { "Authorization" => "Bearer #{token}" }
        }.not_to change { Report.count }
      end
    end

    context "with non-existent post" do
      let(:token) { get_token }

      it "returns not found" do
        post "#{api_base}/posts/99999/report",
             headers: { "Authorization" => "Bearer #{token}" }

        expect(response).to have_http_status(:not_found)
      end
    end

    context "with rate limiting" do
      let(:token) { get_token }

      before do
        # Enable Rack::Attack for these specific tests
        Rack::Attack.enabled = true
        Rack::Attack.cache.clear if Rack::Attack.cache.respond_to?(:clear)
      end

      after do
        # Disable Rack::Attack after tests
        Rack::Attack.enabled = false
      end

      # Note: Rate limiting in tests uses memory store cache, so we need to make
      # all requests in the same test to hit the limit within the cache window
      it "returns rate limit error after 10 reports" do
        # Make 10 API calls to hit rate limit
        other_posts = create_list(:post, 10, author: other_user)
        other_posts.each do |p|
          post "#{api_base}/posts/#{p.id}/report",
               headers: { "Authorization" => "Bearer #{token}" }
        end

        # 11th request should be rate limited
        post "#{api_base}/posts/#{target_post.id}/report",
             headers: { "Authorization" => "Bearer #{token}" }

        expect(response).to have_http_status(:too_many_requests)
        json = JSON.parse(response.body)
        expect(json["error"]).to include("Rate limit exceeded")
      end

      it "includes retry-after header when rate limited" do
        # Make 10 API calls to hit rate limit
        other_posts = create_list(:post, 10, author: other_user)
        other_posts.each do |p|
          post "#{api_base}/posts/#{p.id}/report",
               headers: { "Authorization" => "Bearer #{token}" }
        end

        # 11th request should be rate limited
        post "#{api_base}/posts/#{target_post.id}/report",
             headers: { "Authorization" => "Bearer #{token}" }

        expect(response.headers["Retry-After"]).to be_present
      end
    end
  end
end

