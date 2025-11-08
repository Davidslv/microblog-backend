require 'rails_helper'

RSpec.describe "Api::V1::Admin::Posts", type: :request do
  let(:user) { create(:user) }
  let(:admin) { create(:user, :admin) }
  let(:api_base) { "/api/v1" }

  def get_token(user)
    post "#{api_base}/login", params: { username: user.username, password: "password123" }
    JSON.parse(response.body)["token"]
  end

  describe "POST /api/v1/admin/posts/:id/redact" do
    let(:target_post) { create(:post, author: user) }

    context "when authenticated as admin" do
      let(:token) { get_token(admin) }

      it "redacts a post" do
        post "#{api_base}/admin/posts/#{target_post.id}/redact",
             headers: { "Authorization" => "Bearer #{token}" },
             params: { reason: "inappropriate content" }

        expect(response).to have_http_status(:success)
        target_post.reload
        expect(target_post.redacted?).to be true
        expect(target_post.redaction_reason).to eq("inappropriate content")
      end

      it "logs the redaction in audit trail" do
        post "#{api_base}/admin/posts/#{target_post.id}/redact",
             headers: { "Authorization" => "Bearer #{token}" },
             params: { reason: "test reason" }

        log = ModerationAuditLog.where(action: "redact", post: target_post).last
        expect(log).to be_present
        expect(log.user).to eq(admin)
        expect(log.admin).to eq(admin)
        expect(log.metadata["reason"]).to eq("test reason")
      end

      it "returns error if post is already redacted" do
        target_post.update(redacted: true)

        post "#{api_base}/admin/posts/#{target_post.id}/redact",
             headers: { "Authorization" => "Bearer #{token}" },
             params: { reason: "test" }

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json["error"]).to include("already redacted")
      end
    end

    context "when authenticated as regular user" do
      let(:token) { get_token(user) }

      it "returns forbidden" do
        post "#{api_base}/admin/posts/#{target_post.id}/redact",
             headers: { "Authorization" => "Bearer #{token}" },
             params: { reason: "test" }

        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when not authenticated" do
      it "returns unauthorized" do
        post "#{api_base}/admin/posts/#{target_post.id}/redact",
             params: { reason: "test" }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "POST /api/v1/admin/posts/:id/unredact" do
    let(:target_post) { create(:post, :redacted, author: user) }

    context "when authenticated as admin" do
      let(:token) { get_token(admin) }

      it "unredacts a post" do
        post "#{api_base}/admin/posts/#{target_post.id}/unredact",
             headers: { "Authorization" => "Bearer #{token}" }

        expect(response).to have_http_status(:success)
        target_post.reload
        expect(target_post.redacted?).to be false
        expect(target_post.redaction_reason).to be_nil
      end

      it "logs the unredaction in audit trail" do
        post "#{api_base}/admin/posts/#{target_post.id}/unredact",
             headers: { "Authorization" => "Bearer #{token}" }

        log = ModerationAuditLog.where(action: "unredact", post: target_post).last
        expect(log).to be_present
        expect(log.user).to eq(admin)
        expect(log.admin).to eq(admin)
      end

      it "returns error if post is not redacted" do
        target_post.update(redacted: false)

        post "#{api_base}/admin/posts/#{target_post.id}/unredact",
             headers: { "Authorization" => "Bearer #{token}" }

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json["error"]).to include("not redacted")
      end
    end

    context "when authenticated as regular user" do
      let(:token) { get_token(user) }

      it "returns forbidden" do
        post "#{api_base}/admin/posts/#{target_post.id}/unredact",
             headers: { "Authorization" => "Bearer #{token}" }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "GET /api/v1/admin/posts/:id/reports" do
    let(:target_post) { create(:post, author: user) }

    before do
      create_list(:report, 3, post: target_post)
    end

    context "when authenticated as admin" do
      let(:token) { get_token(admin) }

      it "returns reports for a post" do
        get "#{api_base}/admin/posts/#{target_post.id}/reports",
            headers: { "Authorization" => "Bearer #{token}" }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["reports"].length).to eq(3)
        expect(json["reports"].first).to have_key("id")
        expect(json["reports"].first).to have_key("reporter")
        expect(json["reports"].first).to have_key("created_at")
      end
    end

    context "when authenticated as regular user" do
      let(:token) { get_token(user) }

      it "returns forbidden" do
        get "#{api_base}/admin/posts/#{target_post.id}/reports",
            headers: { "Authorization" => "Bearer #{token}" }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "GET /api/v1/posts with include_redacted" do
    let(:normal_post) { create(:post, author: user) }
    let(:redacted_post) { create(:post, :redacted, author: user) }

    context "when authenticated as admin" do
      let(:token) { get_token(admin) }

      before do
        # Admin follows user to see their posts in feed
        admin.follow(user)
        # Create feed entries for the posts
        FeedEntry.bulk_insert_for_post(normal_post, [admin.id])
        FeedEntry.bulk_insert_for_post(redacted_post, [admin.id])
      end

      it "includes redacted posts when include_redacted=true" do
        get "#{api_base}/posts",
            headers: { "Authorization" => "Bearer #{token}" },
            params: { include_redacted: true }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        post_ids = json["posts"].map { |p| p["id"] }
        expect(post_ids).to include(normal_post.id)
        expect(post_ids).to include(redacted_post.id)
      end

      it "excludes redacted posts when include_redacted=false" do
        # Clear cache to avoid cached results
        Rails.cache.clear
        
        get "#{api_base}/posts",
            headers: { "Authorization" => "Bearer #{token}" },
            params: { include_redacted: false }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        post_ids = json["posts"].map { |p| p["id"] }
        expect(post_ids).to include(normal_post.id)
        expect(post_ids).not_to include(redacted_post.id)
      end
    end

    context "when authenticated as regular user" do
      let(:token) { get_token(user) }

      before do
        # User follows themselves to see their posts in feed
        user.follow(user)
        # Create feed entries for the posts
        FeedEntry.bulk_insert_for_post(normal_post, [user.id])
        FeedEntry.bulk_insert_for_post(redacted_post, [user.id])
      end

      it "ignores include_redacted parameter and excludes redacted posts" do
        get "#{api_base}/posts",
            headers: { "Authorization" => "Bearer #{token}" },
            params: { include_redacted: true }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        post_ids = json["posts"].map { |p| p["id"] }
        expect(post_ids).to include(normal_post.id)
        expect(post_ids).not_to include(redacted_post.id)
      end
    end
  end
end

