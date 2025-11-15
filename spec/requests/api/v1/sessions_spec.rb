require 'rails_helper'

RSpec.describe "Api::V1::Sessions", type: :request do
  let(:user) { create(:user, username: "testuser", password: "password123") }
  let(:api_base) { "/api/v1" }

  describe "POST /api/v1/login" do
    it "logs in with valid credentials and returns JWT token" do
      post "#{api_base}/login", params: { username: user.username, password: "password123" }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["user"]["id"]).to eq(user.id)
      expect(json["user"]["username"]).to eq(user.username)
      expect(json["message"]).to eq("Login successful")
      expect(json["token"]).to be_present

      # Verify token is valid
      payload = JwtService.decode(json["token"])
      expect(payload).to be_present
      expect(payload[:user_id]).to eq(user.id)
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
      token = JSON.parse(response.body)["token"]

      delete "#{api_base}/logout", headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["message"]).to eq("Logged out successfully")

      # Note: JWT is stateless, so token remains valid until expiration
      # In production, you might want to implement token blacklisting
      # For now, we just verify logout endpoint works
    end
  end

  describe "POST /api/v1/refresh" do
    it "refreshes JWT token" do
      # Login first
      post "#{api_base}/login", params: { username: user.username, password: "password123" }
      original_token = JSON.parse(response.body)["token"]
      original_payload = JwtService.decode(original_token)

      # Small delay to ensure different expiration time
      sleep(1)

      # Refresh token
      post "#{api_base}/refresh", headers: { "Authorization" => "Bearer #{original_token}" }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["token"]).to be_present

      # Verify new token has updated expiration
      new_token = json["token"]
      new_payload = JwtService.decode(new_token)
      expect(new_payload[:exp]).to be > original_payload[:exp]

      # Verify new token works
      get "#{api_base}/me", headers: { "Authorization" => "Bearer #{new_token}" }
      expect(response).to have_http_status(:success)
    end

    it "returns unauthorized without valid token" do
      post "#{api_base}/refresh"

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
