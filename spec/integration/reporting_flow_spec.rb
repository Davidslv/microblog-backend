require 'rails_helper'

RSpec.describe "Reporting Flow Integration", type: :request do
  let(:user1) { create(:user) }
  let(:user2) { create(:user) }
  let(:user3) { create(:user) }
  let(:user4) { create(:user) }
  let(:user5) { create(:user) }
  let(:user6) { create(:user) }
  let(:api_base) { "/api/v1" }

  def get_token(user)
    post "#{api_base}/login", params: { username: user.username, password: "password123" }
    JSON.parse(response.body)["token"]
  end

  describe "Complete reporting flow from report to auto-redaction" do
    it "successfully reports a post and triggers auto-redaction at threshold" do
      # Create a post
      post = create(:post, author: user1)

      # Verify post is not redacted initially
      expect(post.redacted?).to be false
      expect(post.report_count).to eq(0)

      # User 2 reports the post
      token2 = get_token(user2)
      post "#{api_base}/posts/#{post.id}/report",
           headers: { "Authorization" => "Bearer #{token2}" }
      expect(response).to have_http_status(:success)

      post.reload
      expect(post.report_count).to eq(1)
      expect(post.redacted?).to be false

      # Verify audit log
      log = ModerationAuditLog.last
      expect(log.action).to eq("report")
      expect(log.post).to eq(post)
      expect(log.user).to eq(user2)

      # Users 3-5 report the post
      [user3, user4, user5].each do |user|
        token = get_token(user)
        post "#{api_base}/posts/#{post.id}/report",
             headers: { "Authorization" => "Bearer #{token}" }
        expect(response).to have_http_status(:success)
      end

      post.reload
      expect(post.report_count).to eq(4)
      expect(post.redacted?).to be false

      # User 6 reports (5th report) - should trigger auto-redaction
      token6 = get_token(user6)
      post "#{api_base}/posts/#{post.id}/report",
           headers: { "Authorization" => "Bearer #{token6}" }
      expect(response).to have_http_status(:success)

      post.reload
      expect(post.redacted?).to be true
      expect(post.redaction_reason).to eq("auto")
      expect(post.redacted_at).to be_present

      # Verify redaction was logged
      redaction_log = ModerationAuditLog.where(action: "redact").last
      expect(redaction_log).to be_present
      expect(redaction_log.post).to eq(post)
      expect(redaction_log.metadata["reason"]).to eq("auto")

      # Verify post is hidden from user queries (silent redaction)
      token = get_token(user2)
      get "#{api_base}/posts/#{post.id}",
          headers: { "Authorization" => "Bearer #{token}" }
      expect(response).to have_http_status(:not_found)

      # Verify post doesn't appear in feed
      get "#{api_base}/posts",
          headers: { "Authorization" => "Bearer #{token}" }
      json = JSON.parse(response.body)
      post_ids = json["posts"].map { |p| p["id"] }
      expect(post_ids).not_to include(post.id)
    end

    it "prevents duplicate reports from same user" do
      post = create(:post, author: user1)
      token = get_token(user2)

      # First report succeeds
      post "#{api_base}/posts/#{post.id}/report",
           headers: { "Authorization" => "Bearer #{token}" }
      expect(response).to have_http_status(:success)

      # Second report from same user fails
      post "#{api_base}/posts/#{post.id}/report",
           headers: { "Authorization" => "Bearer #{token}" }
      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json["error"]).to include("already been reported")

      # Only one report exists
      expect(Report.where(post: post, reporter: user2).count).to eq(1)
    end

    it "prevents self-reporting" do
      post = create(:post, author: user1)
      token = get_token(user1)

      post "#{api_base}/posts/#{post.id}/report",
           headers: { "Authorization" => "Bearer #{token}" }
      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json["error"]).to include("Cannot report your own post")

      # No report created
      expect(Report.where(post: post).count).to eq(0)
    end

    it "handles multiple users reporting the same post correctly" do
      post = create(:post, author: user1)

      # All 5 users report the post
      [user2, user3, user4, user5, user6].each do |user|
        token = get_token(user)
        post "#{api_base}/posts/#{post.id}/report",
             headers: { "Authorization" => "Bearer #{token}" }
        expect(response).to have_http_status(:success)
      end

      post.reload
      expect(post.report_count).to eq(5)
      expect(post.redacted?).to be true

      # Verify all reports exist
      expect(Report.where(post: post).count).to eq(5)
      expect(Report.where(post: post).pluck(:reporter_id)).to match_array([user2, user3, user4, user5, user6].map(&:id))
    end
  end

  describe "Rate limiting integration" do
    it "enforces rate limit across multiple report requests" do
      other_posts = create_list(:post, 11, author: user1)
      token = get_token(user2)

      # Enable Rack::Attack for this test
      Rack::Attack.enabled = true
      Rack::Attack.cache.clear if Rack::Attack.cache.respond_to?(:clear)

      begin
        # Make 10 successful reports
        other_posts[0..9].each do |p|
          post "#{api_base}/posts/#{p.id}/report",
               headers: { "Authorization" => "Bearer #{token}" }
          expect(response).to have_http_status(:success)
        end

        # 11th report should be rate limited
        post "#{api_base}/posts/#{other_posts[10].id}/report",
             headers: { "Authorization" => "Bearer #{token}" }
        expect(response).to have_http_status(:too_many_requests)
      ensure
        Rack::Attack.enabled = false
      end
    end
  end

  describe "Audit trail completeness" do
    it "logs all actions in the reporting flow" do
      post = create(:post, author: user1)

      # Make 5 reports
      [user2, user3, user4, user5, user6].each do |user|
        token = get_token(user)
        post "#{api_base}/posts/#{post.id}/report",
             headers: { "Authorization" => "Bearer #{token}" }
      end

      # Verify audit logs
      logs = ModerationAuditLog.where(post: post).order(:created_at)

      # Should have 5 report logs + 1 redaction log
      expect(logs.count).to eq(6)

      # First 5 should be reports
      logs[0..4].each do |log|
        expect(log.action).to eq("report")
      end

      # Last should be redaction
      expect(logs[5].action).to eq("redact")
      expect(logs[5].metadata["reason"]).to eq("auto")
    end
  end
end

