require 'rails_helper'

RSpec.describe "Api::V1::Users", type: :request do
  let(:user) { create(:user) }
  let(:api_base) { "/api/v1" }

  describe "GET /api/v1/users/:id" do
    it "returns user profile with posts" do
      create_list(:post, 3, author: user)
      
      get "#{api_base}/users/#{user.id}"
      
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["user"]["id"]).to eq(user.id)
      expect(json["user"]["username"]).to eq(user.username)
      expect(json["posts"]).to be_an(Array)
      expect(json["posts"].length).to eq(3)
    end

    it "supports pagination for user posts" do
      create_list(:post, 25, author: user)
      
      get "#{api_base}/users/#{user.id}"
      json = JSON.parse(response.body)
      first_page_posts = json["posts"]
      cursor = json["pagination"]["cursor"]
      
      expect(first_page_posts.length).to eq(20)
      
      # Get next page
      get "#{api_base}/users/#{user.id}", params: { cursor: cursor }
      json = JSON.parse(response.body)
      second_page_posts = json["posts"]
      
      expect(second_page_posts.length).to eq(5)
    end
  end

  describe "POST /api/v1/users (signup)" do
    it "creates a new user" do
      user_params = {
        user: {
          username: "newuser",
          password: "password123",
          password_confirmation: "password123"
        }
      }
      
      expect {
        post "#{api_base}/users", params: user_params
      }.to change(User, :count).by(1)
      
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["user"]["username"]).to eq("newuser")
    end

    it "returns errors for invalid user" do
      user_params = {
        user: {
          username: "",
          password: "short",
          password_confirmation: "different"
        }
      }
      
      post "#{api_base}/users", params: user_params
      
      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json["errors"]).to be_present
    end
  end

  describe "PATCH /api/v1/users/:id" do
    before do
      post "#{api_base}/login", params: { username: user.username, password: "password123" }
    end

    it "updates user profile" do
      patch "#{api_base}/users/#{user.id}", params: {
        user: { description: "Updated description" }
      }
      
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["user"]["description"]).to eq("Updated description")
      expect(user.reload.description).to eq("Updated description")
    end

    it "requires authentication" do
      # Logout first to clear session
      delete "#{api_base}/logout"
      
      patch "#{api_base}/users/#{user.id}", params: {
        user: { description: "Test" }
      }
      
      expect(response).to have_http_status(:unauthorized)
    end

    it "requires ownership" do
      other_user = create(:user)
      # Logout first
      delete "#{api_base}/logout"
      # Login as other user
      post "#{api_base}/login", params: { username: other_user.username, password: "password123" }
      
      patch "#{api_base}/users/#{user.id}", params: {
        user: { description: "Hacked!" }
      }
      
      # Should fail - can't update other user's profile
      expect(response).to have_http_status(:forbidden)
      json = JSON.parse(response.body)
      expect(json["error"]).to include("own profile")
    end
  end

  describe "DELETE /api/v1/users/:id" do
    before do
      post "#{api_base}/login", params: { username: user.username, password: "password123" }
    end

    it "deletes user account" do
      expect {
        delete "#{api_base}/users/#{user.id}"
      }.to change(User, :count).by(-1)
      
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["message"]).to eq("Account deleted successfully")
    end
  end
end

