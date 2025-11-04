require 'rails_helper'

RSpec.describe Follow, type: :model do
  describe 'associations' do
    it { should belong_to(:follower).class_name('User') }
    it { should belong_to(:followed).class_name('User') }
  end

  describe 'validations' do
    let(:user1) { create(:user) }
    let(:user2) { create(:user) }
    let(:follow) { build(:follow, follower: user1, followed: user2) }

    it 'validates uniqueness of follower_id scoped to followed_id' do
      create(:follow, follower: user1, followed: user2)
      expect(follow).not_to be_valid
      expect(follow.errors[:follower_id]).to include('already following this user')
    end

    it 'does not allow following yourself' do
      follow = build(:follow, follower: user1, followed: user1)
      expect(follow).not_to be_valid
      expect(follow.errors[:followed_id]).to include('cannot follow yourself')
    end

    it 'allows valid follow relationships' do
      expect(follow).to be_valid
    end
  end

  describe 'cascade behavior' do
    let(:user1) { create(:user) }
    let(:user2) { create(:user) }
    let!(:follow) { create(:follow, follower: user1, followed: user2) }

    context 'when follower is deleted' do
      it 'deletes the follow relationship' do
        expect { user1.destroy }.to change { Follow.count }.by(-1)
      end
    end

    context 'when followed user is deleted' do
      it 'deletes the follow relationship' do
        expect { user2.destroy }.to change { Follow.count }.by(-1)
      end
    end
  end

  describe 'composite primary key behavior' do
    let(:user1) { create(:user) }
    let(:user2) { create(:user) }
    let(:user3) { create(:user) }

    it 'allows same follower to follow different users' do
      follow1 = create(:follow, follower: user1, followed: user2)
      follow2 = create(:follow, follower: user1, followed: user3)
      expect(Follow.count).to eq(2)
    end

    it 'allows same followed user to have multiple followers' do
      follow1 = create(:follow, follower: user1, followed: user2)
      follow2 = create(:follow, follower: user3, followed: user2)
      expect(Follow.count).to eq(2)
    end
  end
end
