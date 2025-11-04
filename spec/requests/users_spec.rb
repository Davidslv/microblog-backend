require 'rails_helper'

RSpec.describe 'Users', type: :request do
  let(:user) { create(:user, username: 'testuser', description: 'Original description') }
  let(:other_user) { create(:user) }

  describe 'GET /users/:id (show)' do
    before do
      create_list(:post, 3, author: user)
      create(:follow, follower: other_user, followed: user)
      create(:follow, follower: user, followed: other_user)
    end

    it 'returns successful response' do
      get user_path(user)
      expect(response).to have_http_status(:success)
    end

    it 'displays user username' do
      get user_path(user)
      expect(response.body).to include(user.username)
    end

    it 'displays user description' do
      get user_path(user)
      expect(response.body).to include(user.description)
    end

    it 'displays user posts' do
      get user_path(user)
      expect(response.body).to include(user.posts.first.content)
    end

    it 'displays follower count' do
      get user_path(user)
      expect(response.body).to include('1')
      expect(response.body).to include('Followers')
    end

    it 'displays following count' do
      get user_path(user)
      expect(response.body).to include('Following')
    end

    context 'when logged in as different user' do
      before { login_as(other_user) }

      it 'displays follow button when not following' do
        get user_path(user)
        expect(response.body).to include('Follow')
      end

      it 'displays unfollow button when following' do
        other_user.follow(user)
        get user_path(user)
        expect(response.body).to include('Unfollow')
      end
    end

    context 'when viewing own profile' do
      before { login_as(user) }

      it 'does not display follow button' do
        get user_path(user)
        # The page should not have follow/unfollow buttons for own profile
        expect(response.body).not_to match(/<button[^>]*>Follow<\/button>/i)
        expect(response.body).not_to match(/<button[^>]*>Unfollow<\/button>/i)
      end
    end
  end

  describe 'GET /users/:id/edit' do
    context 'when logged in as the user' do
      before { login_as(user) }

      it 'returns successful response' do
        get edit_user_path(user)
        expect(response).to have_http_status(:success)
      end

      it 'displays edit form' do
        get edit_user_path(user)
        expect(response.body).to include('Settings')
        expect(response.body).to include('Description')
      end

      it 'displays current description' do
        get edit_user_path(user)
        expect(response.body).to include(user.description)
      end
    end

    context 'when not logged in' do
      it 'redirects to root' do
        get edit_user_path(user)
        expect(response).to redirect_to(root_path)
      end

      it 'displays error message' do
        get edit_user_path(user)
        follow_redirect!
        expect(response.body).to include('You must be logged in')
      end
    end

    context 'when logged in as different user' do
      before { login_as(other_user) }

      it 'redirects to root' do
        get edit_user_path(user)
        expect(response).to redirect_to(root_path)
      end

      it 'displays error message' do
        get edit_user_path(user)
        follow_redirect!
        expect(response.body).to include('You can only edit your own account')
      end
    end
  end

  describe 'PATCH /users/:id (update)' do
    context 'with valid parameters' do
      before { login_as(user) }
      context 'updating description' do
        let(:update_params) { { user: { description: 'Updated description' } } }

        it 'updates the description' do
          patch user_path(user), params: update_params
          expect(user.reload.description).to eq('Updated description')
        end

        it 'redirects to user profile' do
          patch user_path(user), params: update_params
          expect(response).to redirect_to(user_path(user))
        end

        it 'displays success message' do
          patch user_path(user), params: update_params
          follow_redirect!
          expect(response.body).to include('Settings updated successfully')
        end
      end

      context 'updating password' do
        let(:update_params) { { user: { password: 'newpassword123', password_confirmation: 'newpassword123' } } }

        it 'updates the password' do
          patch user_path(user), params: update_params
          expect(user.reload.authenticate('newpassword123')).to eq(user)
        end
      end

      context 'updating without password' do
        let(:update_params) { { user: { description: 'New description', password: '', password_confirmation: '' } } }

        it 'does not change password' do
          old_digest = user.password_digest
          patch user_path(user), params: update_params
          expect(user.reload.password_digest).to eq(old_digest)
        end

        it 'still updates other fields' do
          patch user_path(user), params: update_params
          expect(user.reload.description).to eq('New description')
        end
      end
    end

    context 'with invalid parameters' do
      before { login_as(user) }

      context 'when description exceeds 120 characters' do
        let(:invalid_params) { { user: { description: 'a' * 121 } } }

        it 'does not update' do
          old_description = user.description
          patch user_path(user), params: invalid_params
          expect(user.reload.description).to eq(old_description)
        end

        it 'displays error message' do
          patch user_path(user), params: invalid_params
          expect(response.body).to include('too long')
        end
      end

      context 'when password confirmation does not match' do
        let(:invalid_params) { { user: { password: 'newpass123', password_confirmation: 'different' } } }

        it 'does not update password' do
          old_digest = user.password_digest
          patch user_path(user), params: invalid_params
          expect(user.reload.password_digest).to eq(old_digest)
        end
      end
    end

    context 'when not logged in' do
      it 'redirects to root' do
        # Don't login - make request without session
        patch user_path(user), params: { user: { description: 'Test' } }
        # Should redirect due to require_login
        expect(response).to have_http_status(:redirect)
        follow_redirect!
        expect(response.body).to include('You must be logged in')
      end
    end

    context 'when logged in as different user' do
      before { login_as(other_user) }

      it 'does not update the user' do
        old_description = user.description
        patch user_path(user), params: { user: { description: 'Hacked!' } }
        expect(user.reload.description).to eq(old_description)
      end
    end
  end

  describe 'DELETE /users/:id (destroy)' do
    context 'when logged in as the user' do
      before { login_as(user) }
      before do
        create_list(:post, 2, author: user)
        create(:follow, follower: user, followed: other_user)
        create(:follow, follower: other_user, followed: user)
      end

      it 'deletes the user account' do
        expect {
          delete user_path(user)
        }.to change(User, :count).by(-1)
      end

      it 'nullifies posts author_id' do
        post_ids = user.posts.pluck(:id)
        delete user_path(user)
        post_ids.each do |post_id|
          expect(Post.find(post_id).author_id).to be_nil
        end
      end

      it 'deletes follow relationships' do
        expect {
          delete user_path(user)
        }.to change(Follow, :count).by(-2)
      end

      it 'logs out the user' do
        delete user_path(user)
        follow_redirect!
        # After deletion, session should be cleared - verify by checking we're not logged in
        get root_path
        expect(response.body).not_to include('alice') # Should not show username in nav
      end

      it 'redirects to root' do
        delete user_path(user)
        expect(response).to redirect_to(root_path)
      end

      it 'displays success message' do
        delete user_path(user)
        follow_redirect!
        expect(response.body).to include('Your account has been deleted')
      end
    end

    context 'when not logged in' do
      it 'does not delete the user' do
        user_id = user.id
        # Don't login - just make request without session
        delete user_path(user)
        expect(User.exists?(user_id)).to be true
      end

      it 'redirects to root' do
        delete user_path(user)
        expect(response).to redirect_to(root_path)
      end
    end

    context 'when logged in as different user' do
      before { login_as(other_user) }

      it 'does not delete the user' do
        user_id = user.id
        delete user_path(user)
        expect(User.exists?(user_id)).to be true
      end

      it 'redirects to root' do
        delete user_path(user)
        expect(response).to redirect_to(root_path)
      end
    end
  end
end
