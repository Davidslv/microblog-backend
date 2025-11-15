require 'rails_helper'

RSpec.describe "Silent Redaction", type: :request do
  let(:user) { create(:user) }
  let(:post_author) { create(:user) }
  let(:api_base) { "/api/v1" }

  def get_token(user)
    post "#{api_base}/login", params: { username: user.username, password: "password123" }
    JSON.parse(response.body)["token"]
  end

  describe "Redacted posts are hidden from users" do
    it "hides redacted posts from post index" do
      token = get_token(user)

      normal_post = create(:post, author: post_author)
      redacted_post = create(:post, :redacted, author: post_author)

      # User follows author to see posts
      user.follow(post_author)
      FeedEntry.bulk_insert_for_post(normal_post, [ user.id ])
      FeedEntry.bulk_insert_for_post(redacted_post, [ user.id ])

      get "#{api_base}/posts",
          headers: { "Authorization" => "Bearer #{token}" }

      json = JSON.parse(response.body)
      post_ids = json["posts"].map { |p| p["id"] }

      expect(post_ids).to include(normal_post.id)
      expect(post_ids).not_to include(redacted_post.id)
    end

    it "returns 404 for redacted posts in show action" do
      token = get_token(user)

      redacted_post = create(:post, :redacted, author: post_author)

      get "#{api_base}/posts/#{redacted_post.id}",
          headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:not_found)
    end

    it "hides redacted posts from post author" do
      token = get_token(post_author)

      normal_post = create(:post, author: post_author)
      redacted_post = create(:post, :redacted, author: post_author)

      # Author follows themselves
      post_author.follow(post_author)
      FeedEntry.bulk_insert_for_post(normal_post, [ post_author.id ])
      FeedEntry.bulk_insert_for_post(redacted_post, [ post_author.id ])

      get "#{api_base}/posts",
          headers: { "Authorization" => "Bearer #{token}" }

      json = JSON.parse(response.body)
      post_ids = json["posts"].map { |p| p["id"] }

      # Even the author cannot see their redacted post (silent redaction)
      expect(post_ids).to include(normal_post.id)
      expect(post_ids).not_to include(redacted_post.id)
    end

    it "hides redacted replies" do
      token = get_token(user)

      parent_post = create(:post, author: post_author)
      normal_reply = create(:post, parent: parent_post, author: post_author)
      redacted_reply = create(:post, :redacted, parent: parent_post, author: post_author)

      get "#{api_base}/posts/#{parent_post.id}",
          headers: { "Authorization" => "Bearer #{token}" }

      json = JSON.parse(response.body)
      reply_ids = json["replies"].map { |r| r["id"] }

      expect(reply_ids).to include(normal_reply.id)
      expect(reply_ids).not_to include(redacted_reply.id)
    end

    it "hides redacted posts from public (unauthenticated) queries" do
      normal_post = create(:post, author: post_author)
      redacted_post = create(:post, :redacted, author: post_author)

      get "#{api_base}/posts"

      json = JSON.parse(response.body)
      post_ids = json["posts"].map { |p| p["id"] }

      expect(post_ids).to include(normal_post.id)
      expect(post_ids).not_to include(redacted_post.id)
    end
  end

  describe "Redacted posts do not appear in user profile" do
    it "excludes redacted posts from user's post list" do
      token = get_token(user)

      normal_post = create(:post, author: post_author)
      redacted_post = create(:post, :redacted, author: post_author)

      get "#{api_base}/users/#{post_author.id}",
          headers: { "Authorization" => "Bearer #{token}" }

      json = JSON.parse(response.body)
      post_ids = json["posts"].map { |p| p["id"] }

      expect(post_ids).to include(normal_post.id)
      # Redacted posts should be filtered from user profile
      expect(post_ids).not_to include(redacted_post.id)
    end
  end
end
