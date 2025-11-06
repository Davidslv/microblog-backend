require 'rails_helper'

RSpec.describe "Api::V1::Sessions", type: :request do
  let(:user) { create(:user, username: "testuser", password: "password123") }
  let(:api_base) { "/api/v1" }

  describe "POST /api/v1/login" do
    it "logs in with valid credentials" do
      post "#{api_base}/login", params: { username: user.username, password: "password123" }
      
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["user"]["id"]).to eq(user.id)
      expect(json["user"]["username"]).to eq(user.username)
      expect(json["message"]).to eq("Login successful")
    end

    it "returns error for invalid credentials" do
      post "#{api_base}/login", params: { username: user.username, password: "wrongpassword" }
      
      expect(response).to have_http_status(:unauthorized)
      json = JSON.parse(response.body)
      expect(json["error"]).to eq("Invalid username or password")
    end

    it "returns error for non-existent user" do
      post "#{api_base}/login", params: { username: "nonexistent", password: "password" }
      
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/me" do
    it "returns current user when authenticated" do
      # Login first
      post "#{api_base}/login", params: { username: user.username, password: "password123" }
      
      get "#{api_base}/me"
      
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["user"]["id"]).to eq(user.id)
      expect(json["user"]["username"]).to eq(user.username)
    end

    it "returns unauthorized when not authenticated" do
      get "#{api_base}/me"
      
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "DELETE /api/v1/logout" do
    it "logs out successfully" do
      # Login first
      post "#{api_base}/login", params: { username: user.username, password: "password123" }
      
      delete "#{api_base}/logout"
      
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["message"]).to eq("Logged out successfully")
      
      # Verify session is cleared
      get "#{api_base}/me"
      expect(response).to have_http_status(:unauthorized)
    end
  end
end

