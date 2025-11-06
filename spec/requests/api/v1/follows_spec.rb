require 'rails_helper'

RSpec.describe "Api::V1::Follows", type: :request do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:api_base) { "/api/v1" }

  before do
    post "#{api_base}/login", params: { username: user.username, password: "password123" }
  end

  describe "POST /api/v1/users/:user_id/follow" do
    it "creates a follow relationship" do
      expect {
        post "#{api_base}/users/#{other_user.id}/follow"
      }.to change(Follow, :count).by(1)
      
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["message"]).to include(other_user.username)
      expect(user.reload.following?(other_user)).to be true
    end

    it "returns error if already following" do
      user.follow(other_user)
      
      post "#{api_base}/users/#{other_user.id}/follow"
      
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "requires authentication" do
      # Don't login
      delete "#{api_base}/logout"
      
      post "#{api_base}/users/#{other_user.id}/follow"
      
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "DELETE /api/v1/users/:user_id/follow" do
    before do
      user.follow(other_user)
    end

    it "removes a follow relationship" do
      expect {
        delete "#{api_base}/users/#{other_user.id}/follow"
      }.to change(Follow, :count).by(-1)
      
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["message"]).to include(other_user.username)
      expect(user.reload.following?(other_user)).to be false
    end

    it "requires authentication" do
      delete "#{api_base}/logout"
      
      delete "#{api_base}/users/#{other_user.id}/follow"
      
      expect(response).to have_http_status(:unauthorized)
    end
  end
end

