require 'rails_helper'

RSpec.describe "Sessions", type: :request do
  let(:user) { create(:user, username: "testuser", password: "password123", password_confirmation: "password123") }

  describe "GET /login" do
    it "displays the login page" do
      get login_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Log in")
    end

    it "redirects to root if already logged in" do
      login_as(user)
      get login_path
      expect(response).to redirect_to(root_path)
    end
  end

  describe "POST /login" do
    context "with valid credentials" do
      it "logs in the user and redirects to root" do
        post "/login", params: { username: user.username, password: "password123" }
        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to include("Welcome back")
      end

      it "sets the session user_id" do
        post "/login", params: { username: user.username, password: "password123" }
        follow_redirect!
        # Session is set in the controller, verify by checking if we can access protected pages
        get posts_path
        expect(response).to have_http_status(:success)
      end
    end

    context "with invalid credentials" do
      it "shows error message for wrong password" do
        post "/login", params: { username: user.username, password: "wrongpassword" }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(flash[:alert]).to include("Invalid username or password")
      end

      it "shows error message for non-existent username" do
        post "/login", params: { username: "nonexistent", password: "password123" }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(flash[:alert]).to include("Invalid username or password")
      end

      it "does not set session for invalid credentials" do
        post "/login", params: { username: user.username, password: "wrongpassword" }
        # Session should not be set
        expect(session[:user_id]).to be_nil
      end
    end

    context "with missing parameters" do
      it "shows error when username is missing" do
        post "/login", params: { password: "password123" }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(flash[:alert]).to be_present
      end

      it "shows error when password is missing" do
        post "/login", params: { username: user.username }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(flash[:alert]).to be_present
      end
    end
  end

  describe "DELETE /logout" do
    it "logs out the user and redirects to root" do
      login_as(user)
      delete logout_path
      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to include("logged out")
    end

    it "clears the session" do
      login_as(user)
      delete logout_path
      # Session should be cleared
      expect(session[:user_id]).to be_nil
    end
  end
end

