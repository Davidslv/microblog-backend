require 'rails_helper'

RSpec.describe "Moderation End-to-End", type: :request do
  let(:user1) { create(:user, username: "user1") }
  let(:user2) { create(:user, username: "user2") }
  let(:user3) { create(:user, username: "user3") }
  let(:user4) { create(:user, username: "user4") }
  let(:user5) { create(:user, username: "user5") }
  let(:user6) { create(:user, username: "user6") }

  let(:api_base) { "/api/v1" }

  def get_token(user)
    post "#{api_base}/login", params: { username: user.username, password: "password123" }
    JSON.parse(response.body)["token"]
  end

  describe "Complete reporting flow" do
    it "allows users to report a post and triggers auto-redaction" do
      # User1 creates a post via API
      token1 = get_token(user1)
      post "#{api_base}/posts",
           headers: { "Authorization" => "Bearer #{token1}" },
           params: { post: { content: "This is a test post" } }

      expect(response).to have_http_status(:success)
      post_obj = Post.last
      expect(post_obj).to be_present
      expect(post_obj.content).to eq("This is a test post")

      # Process feed entries
      perform_enqueued_jobs

      # User2 reports the post
      token2 = get_token(user2)
      post "#{api_base}/posts/#{post_obj.id}/report",
           headers: { "Authorization" => "Bearer #{token2}" }

      expect(response).to have_http_status(:success)
      post_obj.reload
      expect(post_obj.report_count).to eq(1)
      expect(post_obj.redacted?).to be false

      # Users 3-6 also report
      [ user3, user4, user5, user6 ].each do |user|
        token = get_token(user)
        post "#{api_base}/posts/#{post_obj.id}/report",
             headers: { "Authorization" => "Bearer #{token}" }
        expect(response).to have_http_status(:success)
      end

      post_obj.reload
      expect(post_obj.report_count).to eq(5)
      expect(post_obj.redacted?).to be true
      expect(post_obj.redaction_reason).to eq("auto")

      # Post should be hidden from user queries (silent redaction)
      get "#{api_base}/posts",
          headers: { "Authorization" => "Bearer #{token1}" }

      json = JSON.parse(response.body)
      post_ids = json["posts"].map { |p| p["id"] }
      expect(post_ids).not_to include(post_obj.id)
    end
  end
end
