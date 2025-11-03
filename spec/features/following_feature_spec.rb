require 'rails_helper'

RSpec.describe 'Following Feature', type: :feature do
  let(:user) { create(:user, username: 'alice') }
  let(:other_user) { create(:user, username: 'bob') }

  before do
    login_as(user)
  end

  describe 'Following a user' do
    it 'allows user to follow another user from profile page' do
      visit user_path(other_user)

      expect {
        click_button 'Follow'
        # sleep 0.3 # Wait for redirect
      }.to change(Follow, :count).by(1)

      expect(page).to have_content("You are now following #{other_user.username}")
      expect(page).to have_button('Unfollow')
    end

    it 'updates follower count on profile' do
      visit user_path(other_user)
      initial_count = other_user.followers.count

      click_button 'Follow'
      # sleep 0.3

      visit user_path(other_user)
      expect(page).to have_content((initial_count + 1).to_s)
    end

    it 'adds posts to timeline when following' do
      create(:post, author: other_user, content: 'Post from followed user')
      visit user_path(other_user)
      click_button 'Follow'
      # sleep 0.3

      visit root_path
      expect(page).to have_content('Post from followed user')
    end
  end

  describe 'Unfollowing a user' do
    before do
      user.follow(other_user)
    end

    it 'allows user to unfollow from profile page' do
      visit user_path(other_user)

      expect {
        click_button 'Unfollow'
        # sleep 0.3
      }.to change(Follow, :count).by(-1)

      expect(page).to have_content("You have unfollowed #{other_user.username}")
      expect(page).to have_button('Follow')
    end

    it 'removes posts from timeline when unfollowing' do
      create(:post, author: other_user, content: 'Will be removed')
      user.follow(other_user)

      visit root_path
      expect(page).to have_content('Will be removed')

      visit user_path(other_user)
      click_button 'Unfollow'
      # sleep 0.3

      visit root_path
      expect(page).not_to have_content('Will be removed')
    end
  end

  describe 'Following integration with timeline' do
    let(:user3) { create(:user, username: 'charlie') }

    before do
      create(:post, author: user, content: 'My post')
      create(:post, author: other_user, content: 'Bob post')
      create(:post, author: user3, content: 'Charlie post')
    end

    it 'shows posts from followed users in timeline' do
      user.follow(other_user)
      user.follow(user3)

      visit root_path
      click_link 'For You'

      expect(page).to have_content('My post')
      expect(page).to have_content('Bob post')
      expect(page).to have_content('Charlie post')
    end

    it 'shows only followed users posts when filtering' do
      user.follow(other_user)

      visit root_path
      click_link 'Following'

      expect(page).to have_content('Bob post')
      expect(page).not_to have_content('My post')
    end
  end

  describe 'Cannot follow self' do
    it 'does not show follow button on own profile' do
      visit user_path(user)
      expect(page).not_to have_button('Follow')
      expect(page).not_to have_button('Unfollow')
    end
  end
end

