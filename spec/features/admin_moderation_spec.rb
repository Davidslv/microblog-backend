require 'rails_helper'

RSpec.describe "Admin Moderation Workflow", type: :request do
  let(:admin_user) { create(:admin_user, username: "admin", password: "admin123", password_confirmation: "admin123") }
  let(:regular_user) { create(:user, username: "regular") }
  let(:post_author) { create(:user, username: "author") }
  let(:api_base) { "/api/v1" }

  def get_admin_token
    post "#{api_base}/login", params: { username: admin_user.username, password: "admin123" }
    JSON.parse(response.body)["token"]
  rescue
    # If admin login endpoint doesn't exist, create token manually
    JwtService.encode({ user_id: nil, admin_username: admin_user.username })
  end

  def get_user_token(user)
    post "#{api_base}/login", params: { username: user.username, password: "password123" }
    JSON.parse(response.body)["token"]
  end

  describe "Admin authentication and authorization" do
    it "allows admin to access admin endpoints" do
      # Note: Admin authentication would need to be implemented separately
      # For now, we test that a user with matching AdminUser can access
      user = create(:user, username: admin_user.username)
      token = get_user_token(user)

      post = create(:post, author: post_author)

      # Admin should be able to redact
      post "#{api_base}/admin/posts/#{post.id}/redact",
           headers: { "Authorization" => "Bearer #{token}" },
           params: { reason: "inappropriate" }

      expect(response).to have_http_status(:success)
      post.reload
      expect(post.redacted?).to be true
    end

    it "prevents regular users from accessing admin endpoints" do
      user = create(:user)
      token = get_user_token(user)

      post = create(:post, author: post_author)

      post "#{api_base}/admin/posts/#{post.id}/redact",
           headers: { "Authorization" => "Bearer #{token}" },
           params: { reason: "test" }

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "Admin redaction workflow" do
    it "allows admin to manually redact a post" do
      user = create(:user, username: admin_user.username)
      token = get_user_token(user)

      post = create(:post, author: post_author)

      post "#{api_base}/admin/posts/#{post.id}/redact",
           headers: { "Authorization" => "Bearer #{token}" },
           params: { reason: "manual review - inappropriate content" }

      expect(response).to have_http_status(:success)
      post.reload
      expect(post.redacted?).to be true
      expect(post.redaction_reason).to eq("manual review - inappropriate content")

      # Verify audit log
      log = ModerationAuditLog.where(action: "redact", post: post).last
      expect(log).to be_present
      expect(log.metadata["reason"]).to eq("manual review - inappropriate content")
    end

    it "allows admin to unredact a post" do
      user = create(:user, username: admin_user.username)
      token = get_user_token(user)

      post = create(:post, :redacted, author: post_author)

      post "#{api_base}/admin/posts/#{post.id}/unredact",
           headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:success)
      post.reload
      expect(post.redacted?).to be false
      expect(post.redaction_reason).to be_nil

      # Verify audit log
      log = ModerationAuditLog.where(action: "unredact", post: post).last
      expect(log).to be_present
    end

    it "allows admin to view reports for a post" do
      user = create(:user, username: admin_user.username)
      token = get_user_token(user)

      post = create(:post, author: post_author)
      create_list(:report, 3, post: post)

      get "#{api_base}/admin/posts/#{post.id}/reports",
          headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["reports"].length).to eq(3)
    end
  end

  describe "Admin viewing redacted posts" do
    it "allows admin to view redacted posts with include_redacted parameter" do
      user = create(:user, username: admin_user.username)
      token = get_user_token(user)

      normal_post = create(:post, author: post_author)
      redacted_post = create(:post, :redacted, author: post_author)

      # Admin follows author to see posts
      user.follow(post_author)
      FeedEntry.bulk_insert_for_post(normal_post, [ user.id ])
      FeedEntry.bulk_insert_for_post(redacted_post, [ user.id ])

      # Without include_redacted, redacted posts are filtered
      get "#{api_base}/posts",
          headers: { "Authorization" => "Bearer #{token}" },
          params: { include_redacted: false }

      json = JSON.parse(response.body)
      post_ids = json["posts"].map { |p| p["id"] }
      expect(post_ids).to include(normal_post.id)
      expect(post_ids).not_to include(redacted_post.id)

      # With include_redacted=true, admin can see redacted posts
      get "#{api_base}/posts",
          headers: { "Authorization" => "Bearer #{token}" },
          params: { include_redacted: true }

      json = JSON.parse(response.body)
      post_ids = json["posts"].map { |p| p["id"] }
      expect(post_ids).to include(normal_post.id)
      expect(post_ids).to include(redacted_post.id)
    end
  end
end
