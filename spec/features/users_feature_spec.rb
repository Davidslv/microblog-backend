require 'rails_helper'

RSpec.describe 'Users Feature', type: :feature do
  let(:user) { create(:user, username: 'alice', description: 'Original description') }
  let(:other_user) { create(:user, username: 'bob') }

  describe 'Viewing user profile' do
    before do
      create_list(:post, 5, author: other_user)
      create(:follow, follower: user, followed: other_user)
      # Create a follower for other_user (not self-following)
      third_user = create(:user)
      create(:follow, follower: third_user, followed: other_user)
    end

    it 'displays user information' do
      visit user_path(other_user)

      expect(page).to have_content('bob')
      expect(page).to have_content('5')
      expect(page).to have_content('Posts')
      expect(page).to have_content('2')
      expect(page).to have_content('Followers')
    end

    it 'displays user posts' do
      visit user_path(other_user)

      expect(page).to have_content(other_user.posts.first.content)
      expect(page).to have_content(other_user.posts.last.content)
    end

    context 'when logged in as different user' do
      before { login_as(user) }

      it 'shows follow button when not following' do
        # Make sure user is not already following
        user.unfollow(other_user) if user.following?(other_user)
        visit user_path(other_user)
        expect(page).to have_button('Follow')
      end

      it 'shows unfollow button when following' do
        user.follow(other_user)
        visit user_path(other_user)
        expect(page).to have_button('Unfollow')
      end
    end

    context 'when viewing own profile' do
      before do
        login_as(user)
        visit user_path(user)
      end

      it 'does not show follow/unfollow button' do
        expect(page).not_to have_button('Follow')
        expect(page).not_to have_button('Unfollow')
      end
    end
  end

  describe 'Editing user settings' do
    before do
      login_as(user)
      visit edit_user_path(user)
    end

    it 'allows updating description' do
      fill_in 'Description', with: 'Updated description text'
      click_button 'Update Settings'

      expect(page).to have_content('Settings updated successfully')
      expect(page).to have_content('Updated description text')
    end

    it 'allows updating password' do
      fill_in 'New Password (leave blank to keep current)', with: 'newpassword123'
      fill_in 'Confirm New Password', with: 'newpassword123'
      click_button 'Update Settings'

      expect(page).to have_content('Settings updated successfully')
      expect(user.reload.authenticate('newpassword123')).to eq(user)
    end

    it 'does not require password to update description' do
      fill_in 'Description', with: 'New description without password'
      click_button 'Update Settings'

      expect(page).to have_content('Settings updated successfully')
      expect(user.reload.description).to eq('New description without password')
    end

    it 'validates description length' do
      fill_in 'Description', with: 'a' * 121
      click_button 'Update Settings'

      expect(page).to have_content('too long')
    end

    it 'validates password confirmation' do
      fill_in 'New Password (leave blank to keep current)', with: 'newpass123'
      fill_in 'Confirm New Password', with: 'different'
      click_button 'Update Settings'

      expect(page).to have_content('doesn\'t match')
    end

    it 'has link to cancel' do
      click_link 'Cancel'
      expect(page).to have_current_path(user_path(user))
    end
  end

  describe 'Deleting account' do
    before do
      login_as(user)
      create_list(:post, 3, author: user)
      create(:follow, follower: user, followed: other_user)
    end

    it 'allows user to delete their account' do
      visit edit_user_path(user)

      expect {
        if Capybara.current_driver == :rack_test
          click_button 'Delete Account'
        else
          page.accept_confirm do
            click_button 'Delete Account'
          end
        end
        # sleep 0.3 # Wait for redirect
      }.to change(User, :count).by(-1)
    end

    it 'keeps posts but nullifies author' do
      post_ids = user.posts.pluck(:id)
      visit edit_user_path(user)

      if Capybara.current_driver == :rack_test
        click_button 'Delete Account'
      else
        page.accept_confirm do
          click_button 'Delete Account'
        end
      end

      post_ids.each do |post_id|
        expect(Post.find(post_id).author_id).to be_nil
        expect(Post.find(post_id).author_name).to eq('Deleted User')
      end
    end

    it 'deletes follow relationships' do
      expect {
        visit edit_user_path(user)
        if Capybara.current_driver == :rack_test
          click_button 'Delete Account'
        else
          page.accept_confirm do
            click_button 'Delete Account'
          end
        end
        # sleep 0.1
      }.to change(Follow, :count).by(-1)
    end

    it 'redirects to home page after deletion' do
      visit edit_user_path(user)
      if Capybara.current_driver == :rack_test
        click_button 'Delete Account'
      else
        page.accept_confirm do
          click_button 'Delete Account'
        end
      end

      expect(page).to have_current_path(root_path)
      expect(page).to have_content('Your account has been deleted')
    end
  end

  describe 'Access control' do
    it 'prevents viewing edit page when not logged in' do
      # Don't login - just visit without session
      visit edit_user_path(user)

      expect(page).to have_current_path(root_path)
      expect(page).to have_content('You must be logged in')
    end

    it 'prevents editing other users accounts' do
      login_as(other_user)
      visit edit_user_path(user)

      expect(page).to have_current_path(root_path)
      expect(page).to have_content('You can only edit your own account')
    end
  end
end
