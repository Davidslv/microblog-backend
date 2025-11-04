require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'associations' do
    it { should have_many(:posts).with_foreign_key('author_id').dependent(:nullify) }
    it { should have_many(:active_follows).class_name('Follow').with_foreign_key('follower_id').dependent(:delete_all) }
    it { should have_many(:passive_follows).class_name('Follow').with_foreign_key('followed_id').dependent(:delete_all) }
    it { should have_many(:following).through(:active_follows).source(:followed) }
    it { should have_many(:followers).through(:passive_follows).source(:follower) }
  end

  describe 'validations' do
    subject { build(:user) }

    it { should validate_presence_of(:username) }
    it { should validate_uniqueness_of(:username) }
    it { should validate_length_of(:username).is_at_most(50) }
    it { should validate_length_of(:description).is_at_most(120).allow_nil }
    it { should validate_length_of(:password).is_at_least(6).allow_blank }
    it { should have_secure_password }
  end

  describe '#follow' do
    let(:user1) { create(:user) }
    let(:user2) { create(:user) }

    context 'when following a valid user' do
      it 'creates a follow relationship' do
        expect { user1.follow(user2) }.to change { Follow.count }.by(1)
      end

      it 'returns truthy value' do
        expect(user1.follow(user2)).to be_truthy
      end

      it 'adds user2 to user1 following list' do
        user1.follow(user2)
        expect(user1.following).to include(user2)
      end

      it 'adds user1 to user2 followers list' do
        user1.follow(user2)
        expect(user2.followers).to include(user1)
      end
    end

    context 'when trying to follow self' do
      it 'does not create a follow relationship' do
        expect { user1.follow(user1) }.not_to change { Follow.count }
      end

      it 'returns false' do
        expect(user1.follow(user1)).to be false
      end
    end

    context 'when already following the user' do
      before { user1.follow(user2) }

      it 'does not create a duplicate follow relationship' do
        expect { user1.follow(user2) }.not_to change { Follow.count }
      end

      it 'returns false' do
        expect(user1.follow(user2)).to be false
      end
    end
  end

  describe '#unfollow' do
    let(:user1) { create(:user) }
    let(:user2) { create(:user) }

    before { user1.follow(user2) }

    it 'removes the follow relationship' do
      expect { user1.unfollow(user2) }.to change { Follow.count }.by(-1)
    end

    it 'removes user2 from user1 following list' do
      user1.unfollow(user2)
      # Reload to clear cached associations
      user1.reload
      expect(user1.following).not_to include(user2)
    end

    it 'removes user1 from user2 followers list' do
      user1.unfollow(user2)
      # Reload to clear cached associations
      user2.reload
      expect(user2.followers).not_to include(user1)
    end

    context 'when not following the user' do
      before do
        user1.unfollow(user2)
        user1.reload
      end

      it 'does not raise an error' do
        expect { user1.unfollow(user2) }.not_to raise_error
      end

      it 'returns false when not following' do
        result = user1.unfollow(user2)
        expect(result).to be false
      end
    end
  end

  describe '#following?' do
    let(:user1) { create(:user) }
    let(:user2) { create(:user) }

    context 'when following the user' do
      before { user1.follow(user2) }

      it 'returns true' do
        expect(user1.following?(user2)).to be true
      end
    end

    context 'when not following the user' do
      it 'returns false' do
        expect(user1.following?(user2)).to be false
      end
    end
  end

  describe '#feed_posts' do
    let(:user1) { create(:user) }
    let(:user2) { create(:user) }
    let(:user3) { create(:user) }

    before do
      # Create posts for each user
      create_list(:post, 2, author: user1)
      create_list(:post, 3, author: user2)
      create_list(:post, 1, author: user3)

      # User1 follows user2 and user3
      user1.follow(user2)
      user1.follow(user3)
    end

    it 'includes posts from the user' do
      feed = user1.feed_posts
      expect(feed.pluck(:author_id)).to include(user1.id)
    end

    it 'includes posts from followed users' do
      feed = user1.feed_posts
      expect(feed.pluck(:author_id)).to include(user2.id, user3.id)
    end

    it 'does not include posts from non-followed users' do
      user4 = create(:user)
      create(:post, author: user4)
      feed = user1.feed_posts
      expect(feed.pluck(:author_id)).not_to include(user4.id)
    end

    it 'returns all posts from user and followed users' do
      feed = user1.feed_posts
      expect(feed.count).to eq(6) # 2 from user1 + 3 from user2 + 1 from user3
    end
  end

  describe 'password encryption' do
    let(:user) { create(:user, password: 'password123') }

    it 'encrypts the password' do
      expect(user.password_digest).not_to eq('password123')
      expect(user.password_digest).to be_present
    end

    it 'can authenticate with correct password' do
      expect(user.authenticate('password123')).to eq(user)
    end

    it 'cannot authenticate with incorrect password' do
      expect(user.authenticate('wrong_password')).to be false
    end
  end
end
