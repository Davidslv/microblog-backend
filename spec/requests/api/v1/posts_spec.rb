require 'rails_helper'

RSpec.describe "Api::V1::Posts", type: :request do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:api_base) { "/api/v1" }

  describe "GET /api/v1/posts" do
    context "when not authenticated" do
      it "returns public posts" do
        create_list(:post, 3)
        
        get "#{api_base}/posts"
        
        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["posts"]).to be_an(Array)
        expect(json["posts"].length).to eq(3)
        expect(json["pagination"]).to be_present
        expect(json["pagination"]["has_next"]).to be_in([true, false])
      end

      it "supports cursor-based pagination" do
        posts = create_list(:post, 25)
        
        get "#{api_base}/posts"
        json = JSON.parse(response.body)
        first_page_posts = json["posts"]
        cursor = json["pagination"]["cursor"]
        
        expect(first_page_posts.length).to eq(20)
        expect(cursor).to be_present
        
        # Get next page
        get "#{api_base}/posts", params: { cursor: cursor }
        json = JSON.parse(response.body)
        second_page_posts = json["posts"]
        
        expect(second_page_posts.length).to eq(5)
        expect(second_page_posts.map { |p| p["id"] }).not_to include(*first_page_posts.map { |p| p["id"] })
      end
    end

    context "when authenticated" do
      before do
        # Login via API - maintain cookies for session
        post "#{api_base}/login", params: { username: user.username, password: "password123" }
      end

      it "returns user's feed posts" do
        # Create posts from followed user
        followed_user = create(:user)
        user.follow(followed_user)
        create(:post, author: followed_user)
        
        get "#{api_base}/posts"
        
        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["posts"]).to be_an(Array)
        expect(json["posts"].first["author"]["username"]).to eq(followed_user.username)
      end

      it "supports filter=mine" do
        create(:post, author: user)
        create(:post, author: other_user)
        
        get "#{api_base}/posts", params: { filter: "mine" }
        
        json = JSON.parse(response.body)
        expect(json["posts"].all? { |p| p["author"]["id"] == user.id }).to be true
      end

      it "supports filter=following" do
        followed_user = create(:user)
        user.follow(followed_user)
        create(:post, author: followed_user)
        create(:post, author: other_user)
        
        get "#{api_base}/posts", params: { filter: "following" }
        
        json = JSON.parse(response.body)
        expect(json["posts"].all? { |p| p["author"]["id"] == followed_user.id }).to be true
      end
    end
  end

  describe "GET /api/v1/posts/:id" do
    let(:post) { create(:post, author: user) }
    let(:replies) { create_list(:post, 3, parent: post, author: other_user) }

    it "returns post with replies" do
      replies
      
      get "#{api_base}/posts/#{post.id}"
      
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["post"]["id"]).to eq(post.id)
      expect(json["replies"]).to be_an(Array)
      expect(json["replies"].length).to eq(3)
    end

    it "supports pagination for replies" do
      create_list(:post, 25, parent: post, author: other_user)
      
      get "#{api_base}/posts/#{post.id}"
      json = JSON.parse(response.body)
      first_page_replies = json["replies"]
      cursor = json["pagination"]["cursor"]
      
      expect(first_page_replies.length).to eq(20)
      
      # Get next page of replies
      get "#{api_base}/posts/#{post.id}", params: { replies_cursor: cursor }
      json = JSON.parse(response.body)
      second_page_replies = json["replies"]
      
      expect(second_page_replies.length).to eq(5)
    end
  end

  describe "POST /api/v1/posts" do
    let(:token) do
      post "#{api_base}/login", params: { username: user.username, password: "password123" }
      JSON.parse(response.body)["token"]
    end

    it "creates a new post with JWT token" do
      post_params = { post: { content: "Hello from API!" } }
      
      expect {
        post "#{api_base}/posts", params: post_params, headers: { "Authorization" => "Bearer #{token}" }
      }.to change(Post, :count).by(1)
      
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["post"]["content"]).to eq("Hello from API!")
      expect(json["post"]["author"]["id"]).to eq(user.id)
    end

    it "creates a reply" do
      parent_post = create(:post)
      post_params = { post: { content: "This is a reply", parent_id: parent_post.id } }
      
      expect {
        post "#{api_base}/posts", params: post_params, headers: { "Authorization" => "Bearer #{token}" }
      }.to change(Post, :count).by(1)
      
      json = JSON.parse(response.body)
      expect(json["post"]["parent_id"]).to eq(parent_post.id)
    end

    it "returns errors for invalid post" do
      post_params = { post: { content: "" } }
      
      post "#{api_base}/posts", params: post_params, headers: { "Authorization" => "Bearer #{token}" }
      
      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json["errors"]).to be_present
    end

    it "requires authentication" do
      post "#{api_base}/posts", params: { post: { content: "Test" } }
      
      expect(response).to have_http_status(:unauthorized)
    end
  end
end

