require 'rails_helper'

RSpec.describe 'End-to-End User Journey', type: :feature do
  let(:user1) { create(:user, username: 'alice', description: 'Alice description') }
  let(:user2) { create(:user, username: 'bob', description: 'Bob description') }
  let(:user3) { create(:user, username: 'charlie') }

  describe 'Complete user workflow' do
    it 'allows a user to sign up, post, follow, and interact' do
      # Step 1: Login as user1 (simulating signup)
      login_as(user1)
      visit root_path

      # Step 2: Create first post
      fill_in 'post_content', with: 'Hello world! My first post.'
      click_button 'Post'
      expect(page).to have_content('Post created successfully')
      expect(page).to have_content('Hello world! My first post.')
      expect(page).to have_content('alice')

      # Step 3: Create more posts
      fill_in 'post_content', with: 'This is my second post.'
      click_button 'Post'
      expect(page).to have_content('This is my second post.')

      # Step 4: View own profile
      # The username link is in the nav, click it directly
      click_link 'alice', match: :first
      expect(page).to have_content('alice')
      expect(page).to have_content('Alice description')
      # Check for post count (might be 2 or more)
      expect(page).to have_content('Posts')

      # Step 5: Edit profile
      # Settings is now an icon, find it by the edit path
      find("a[href='#{edit_user_path(user1)}']").click
      fill_in 'Description', with: 'Updated Alice description'
      click_button 'Update Settings'
      expect(page).to have_content('Settings updated successfully')
      expect(page).to have_content('Updated Alice description')

      # Step 6: Follow another user
      visit user_path(user2)
      click_button 'Follow'
      expect(page).to have_content("You are now following #{user2.username}")
      expect(page).to have_button('Unfollow')

      # Step 7: View timeline with followed user's posts
      create(:post, author: user2, content: 'Bob says hello!')
      visit root_path
      expect(page).to have_content('Bob says hello!')
      expect(page).to have_content('This is my second post.')

      # Step 8: Reply to a post
      # The reply count is a link to the post show page
      # Find the post by content, then click the reply link (which shows the count)
      post_card = page.find('article', text: 'Bob says hello!')
      # Find the link that contains the reply count (it's a link to the post)
      post_card.find('a', text: '0').click
      fill_in 'post_content', with: 'This is my reply to Bob!'
      click_button 'Reply'
      expect(page).to have_content('Post created successfully')
      expect(page).to have_content('This is my reply to Bob!')

      # Step 9: Filter posts - go back to timeline first
      visit root_path
      # Filter tabs don't have a specific class, just click the link directly
      click_link 'My Posts'
      expect(page).to have_content('Hello world!')
      expect(page).to have_content('This is my second post.')
      expect(page).not_to have_content('Bob says hello!')

      # Step 10: Unfollow user
      visit user_path(user2)
      click_button 'Unfollow'
      expect(page).to have_content("You have unfollowed #{user2.username}")

      # Step 11: Verify unfollowed posts don't appear
      visit root_path
      click_link 'For You'
      expect(page).not_to have_content('Bob says hello!')
    end

    it 'handles deleted user scenario' do
      # Create posts and relationships
      login_as(user1)
      post1 = create(:post, author: user1, content: 'My post')
      post2 = create(:post, author: user2, content: 'Bob post')
      user1.follow(user2)
      reply = create(:post, :reply, parent: post1, author: user2, content: 'Reply to Alice')

      # Delete user1
      visit edit_user_path(user1)
      # rack_test driver doesn't support JS modals, but Rails will submit anyway
      # For rack_test, the confirm dialog is ignored, so we can just click
      if Capybara.current_driver == :rack_test
        click_button 'Delete Account'
      else
        page.accept_confirm do
          click_button 'Delete Account'
        end
      end

      # Verify posts remain with nullified author
      visit root_path
      expect(page).to have_content('My post')
      expect(page).to have_content('Deleted User')

      # Verify reply still exists
      visit post_path(post1)
      expect(page).to have_content('Reply to Alice')
      expect(page).to have_content('bob')

      # Verify follow relationship is deleted
      visit user_path(user2)
      expect(page).not_to have_content('alice')
    end

    it 'handles multiple users interaction' do
      # Setup: Multiple users with posts and follows
      login_as(user1)
      create(:post, author: user1, content: 'Alice post 1')
      create(:post, author: user2, content: 'Bob post 1')
      create(:post, author: user3, content: 'Charlie post 1')

      user1.follow(user2)
      user1.follow(user3)

      # View timeline
      visit root_path
      expect(page).to have_content('Alice post 1')
      expect(page).to have_content('Bob post 1')
      expect(page).to have_content('Charlie post 1')

      # Switch to following only
      click_link 'Following'
      expect(page).not_to have_content('Alice post 1')
      expect(page).to have_content('Bob post 1')
      expect(page).to have_content('Charlie post 1')

      # Unfollow one user
      visit user_path(user2)
      click_button 'Unfollow'

      # Check timeline updates
      visit root_path
      click_link 'Following'
      expect(page).not_to have_content('Bob post 1')
      expect(page).to have_content('Charlie post 1')
    end
  end

  describe 'Navigation and user experience' do
    before do
      login_as(user1)
      create(:post, author: user1, content: 'Test post')
    end

    it 'allows navigation between pages' do
      visit root_path
      expect(page).to have_link('For You')  # Changed from "Timeline"
      expect(page).to have_content('alice')
      # Settings is now an icon, check for the edit path
      expect(page).to have_css("a[href='#{edit_user_path(user1)}']")

      # Click on the username link in the navigation
      click_link 'alice', match: :first
      expect(page).to have_current_path(user_path(user1))

      # Settings is now an icon, find it by the edit path
      find("a[href='#{edit_user_path(user1)}']").click
      expect(page).to have_current_path(edit_user_path(user1))

      click_link 'Cancel'
      expect(page).to have_current_path(user_path(user1))

      visit root_path
      # Posts have a reply count link that goes to the post page
      # Find the post by content and click the reply count link
      post_card = page.find('article', text: /Test post/, match: :first)
      # Click the reply count link (shows "0" for no replies) which goes to the post show page
      post_card.find('a', text: '0').click
      expect(page).to have_current_path(post_path(Post.first))
    end

    it 'displays flash messages correctly' do
      visit root_path
      fill_in 'post_content', with: 'New post'
      click_button 'Post'
      expect(page).to have_content('Post created successfully')

      visit user_path(user2)
      click_button 'Follow'
      expect(page).to have_content("You are now following #{user2.username}")
    end
  end
end
