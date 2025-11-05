require 'rails_helper'

RSpec.describe "Authentication Flow", type: :feature do
  let(:user) { create(:user, username: "testuser", password: "password123", password_confirmation: "password123") }

  describe "Signup flow" do
    it "allows a new user to sign up" do
      visit signup_path
      expect(page).to have_content("Sign up")

      fill_in "Username", with: "newuser"
      fill_in "Password", with: "password123"
      fill_in "Confirm Password", with: "password123"
      click_button "Sign up"

      expect(page).to have_content("Welcome to Microblog")
      expect(page).to have_content("newuser")
      expect(page).to have_current_path(root_path)
    end

    it "shows validation errors for invalid signup" do
      visit signup_path
      fill_in "Username", with: ""  # Missing username
      fill_in "Password", with: "short"  # Too short
      fill_in "Confirm Password", with: "different"  # Mismatch
      click_button "Sign up"

      expect(page).to have_content("Sign up")  # Still on signup page
      expect(page).to have_content("can't be blank")  # Username error
    end

    it "prevents duplicate username signup" do
      create(:user, username: "existing")
      visit signup_path
      fill_in "Username", with: "existing"
      fill_in "Password", with: "password123"
      fill_in "Confirm Password", with: "password123"
      click_button "Sign up"

      expect(page).to have_content("Sign up")  # Still on signup page
      expect(page).to have_content("has already been taken")
    end

    it "redirects to root if already logged in" do
      login_as(user)
      visit signup_path
      expect(page).to have_current_path(root_path)
    end
  end

  describe "Login flow" do
    it "allows a user to log in" do
      visit login_path
      expect(page).to have_content("Log in")

      fill_in "Username", with: user.username
      fill_in "Password", with: "password123"
      click_button "Log in"

      expect(page).to have_content("Welcome back")
      expect(page).to have_content(user.username)
      expect(page).to have_current_path(root_path)
    end

    it "shows error for invalid credentials" do
      visit login_path
      fill_in "Username", with: user.username
      fill_in "Password", with: "wrongpassword"
      click_button "Log in"

      expect(page).to have_content("Invalid username or password")
      expect(page).to have_content("Log in")  # Still on login page
    end

    it "shows error for non-existent user" do
      visit login_path
      fill_in "Username", with: "nonexistent"
      fill_in "Password", with: "password123"
      click_button "Log in"

      expect(page).to have_content("Invalid username or password")
    end

    it "redirects to root if already logged in" do
      login_as(user)
      visit login_path
      expect(page).to have_current_path(root_path)
    end
  end

  describe "Logout flow" do
    it "allows a user to log out" do
      login_as(user)
      visit root_path
      expect(page).to have_content(user.username)

      # Find and click the logout button
      find("form[action='#{logout_path}'] button").click

      expect(page).to have_content("logged out")
      expect(page).to have_current_path(root_path)
      expect(page).to have_link("Log in")
      expect(page).to have_link("Sign up")
      expect(page).not_to have_content(user.username)
    end
  end

  describe "Navigation links" do
    context "when logged out" do
      it "shows login and signup links" do
        visit root_path
        expect(page).to have_link("Log in")
        expect(page).to have_link("Sign up")
        expect(page).not_to have_content(user.username)
      end
    end

    context "when logged in" do
      it "shows user profile and logout links" do
        login_as(user)
        visit root_path
        expect(page).to have_content(user.username)
        expect(page).to have_link(user.username)  # Profile link
        expect(page).to have_css("form[action='#{logout_path}']")  # Logout button
        expect(page).not_to have_link("Log in")
        expect(page).not_to have_link("Sign up")
      end
    end
  end

  describe "Protected routes" do
    it "requires login to create a post" do
      visit root_path
      # Post form is not shown when logged out
      expect(page).not_to have_field("post_content")
      expect(page).to have_content("Log in")
      expect(page).to have_content("You're viewing public posts")
    end

    it "allows logged in users to create posts" do
      login_as(user)
      visit root_path
      fill_in "post_content", with: "Test post"
      click_button "Post"

      expect(page).to have_content("Post created successfully")
      expect(page).to have_content("Test post")
    end
  end

  describe "End-to-end authentication flow" do
    it "completes full signup, login, and logout cycle" do
      # Signup
      visit signup_path
      fill_in "Username", with: "enduser"
      fill_in "Password", with: "password123"
      fill_in "Confirm Password", with: "password123"
      click_button "Sign up"

      expect(page).to have_content("Welcome to Microblog")
      expect(page).to have_content("enduser")

      # Create a post (verify logged in)
      fill_in "post_content", with: "My first post"
      click_button "Post"
      expect(page).to have_content("Post created successfully")

      # Logout
      find("form[action='#{logout_path}'] button").click
      expect(page).to have_content("logged out")
      expect(page).to have_link("Log in")

      # Login again
      click_link "Log in"
      fill_in "Username", with: "enduser"
      fill_in "Password", with: "password123"
      click_button "Log in"

      expect(page).to have_content("Welcome back")
      expect(page).to have_content("enduser")
      expect(page).to have_content("My first post")  # Post still exists
    end
  end
end

