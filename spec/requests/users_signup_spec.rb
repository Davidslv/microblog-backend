require 'rails_helper'

RSpec.describe "User Signup", type: :request do
  describe "GET /signup" do
    it "displays the signup page" do
      get signup_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Sign up")
    end

    it "redirects to root if already logged in" do
      user = create(:user)
      login_as(user)
      get signup_path
      expect(response).to redirect_to(root_path)
    end
  end

  describe "POST /signup" do
    context "with valid parameters" do
      it "creates a new user" do
        expect {
          post "/users", params: {
            user: {
              username: "newuser",
              password: "password123",
              password_confirmation: "password123"
            }
          }
        }.to change(User, :count).by(1)
      end

      it "logs in the user automatically after signup" do
        post "/users", params: {
          user: {
            username: "newuser",
            password: "password123",
            password_confirmation: "password123"
          }
        }
        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to include("Welcome to Microblog")

        # Verify user is logged in by accessing protected page
        follow_redirect!
        get posts_path
        expect(response).to have_http_status(:success)
      end

      it "sets the session user_id" do
        post "/users", params: {
          user: {
            username: "newuser",
            password: "password123",
            password_confirmation: "password123"
          }
        }
        # Session should be set
        follow_redirect!
        get posts_path
        expect(response).to have_http_status(:success)
      end
    end

    context "with invalid parameters" do
      it "does not create user with duplicate username" do
        existing_user = create(:user, username: "existing")
        expect {
          post "/users", params: {
            user: {
              username: "existing",
              password: "password123",
              password_confirmation: "password123"
            }
          }
        }.not_to change(User, :count)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(flash[:alert]).to be_present
      end

      it "does not create user with password too short" do
        expect {
          post "/users", params: {
            user: {
              username: "newuser",
              password: "short",
              password_confirmation: "short"
            }
          }
        }.not_to change(User, :count)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(flash[:alert]).to be_present
      end

      it "does not create user with mismatched passwords" do
        expect {
          post "/users", params: {
            user: {
              username: "newuser",
              password: "password123",
              password_confirmation: "different"
            }
          }
        }.not_to change(User, :count)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(flash[:alert]).to be_present
      end

      it "does not create user with missing username" do
        expect {
          post "/users", params: {
            user: {
              password: "password123",
              password_confirmation: "password123"
            }
          }
        }.not_to change(User, :count)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(flash[:alert]).to be_present
      end

      it "does not create user with username too long" do
        expect {
          post "/users", params: {
            user: {
              username: "a" * 51, # 51 characters (max is 50)
              password: "password123",
              password_confirmation: "password123"
            }
          }
        }.not_to change(User, :count)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(flash[:alert]).to be_present
      end
    end
  end
end

