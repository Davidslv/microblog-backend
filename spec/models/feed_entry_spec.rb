require 'rails_helper'

RSpec.describe FeedEntry, type: :model do
  describe 'associations' do
    it { should belong_to(:user) }
    it { should belong_to(:post) }
    it { should belong_to(:author).class_name('User') }
  end

  describe 'validations' do
    let(:user) { create(:user) }
    let(:author) { create(:user) }
    let(:post) { create(:post, author: author) }

    subject { build(:feed_entry, user: user, post: post, author: author) }

    it { should validate_presence_of(:user_id) }
    it { should validate_presence_of(:post_id) }
    it { should validate_presence_of(:author_id) }
    it { should validate_presence_of(:created_at) }

    it 'validates uniqueness of user_id scoped to post_id' do
      create(:feed_entry, user: user, post: post, author: author)
      duplicate = build(:feed_entry, user: user, post: post, author: author)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:user_id]).to be_present
    end
  end

  describe 'scopes' do
    let(:user1) { create(:user) }
    let(:user2) { create(:user) }
    let(:author) { create(:user) }
    let(:post1) { create(:post, author: author, created_at: 3.days.ago) }
    let(:post2) { create(:post, author: author, created_at: 2.days.ago) }
    let(:post3) { create(:post, author: author, created_at: 1.day.ago) }

    before do
      create(:feed_entry, user: user1, post: post1, author: author, created_at: post1.created_at)
      create(:feed_entry, user: user1, post: post2, author: author, created_at: post2.created_at)
      create(:feed_entry, user: user1, post: post3, author: author, created_at: post3.created_at)
      create(:feed_entry, user: user2, post: post1, author: author, created_at: post1.created_at)
    end

    describe '.for_user' do
      it 'returns feed entries for a specific user' do
        entries = FeedEntry.for_user(user1.id)
        expect(entries.count).to eq(3)
        expect(entries.pluck(:user_id).uniq).to eq([user1.id])
      end
    end

    describe '.from_author' do
      it 'returns feed entries from a specific author' do
        entries = FeedEntry.from_author(author.id)
        expect(entries.count).to eq(4)
        expect(entries.pluck(:author_id).uniq).to eq([author.id])
      end
    end

    describe '.recent' do
      it 'orders entries by created_at descending' do
        entries = FeedEntry.for_user(user1.id).recent
        expect(entries.first.post_id).to eq(post3.id) # newest
        expect(entries.last.post_id).to eq(post1.id) # oldest
      end
    end

    describe '.old' do
      it 'returns entries older than 30 days' do
        # Create a new post and entry that's old
        old_post = create(:post, author: author, created_at: 31.days.ago)
        old_entry = create(:feed_entry,
          user: user1,
          post: old_post,
          author: author,
          created_at: 31.days.ago
        )
        recent_entry = FeedEntry.for_user(user1.id).where(post_id: post2.id).first

        entries = FeedEntry.old
        expect(entries).to include(old_entry)
        expect(entries).not_to include(recent_entry) if recent_entry
      end
    end
  end

  describe '.bulk_insert_for_post' do
    let(:author) { create(:user) }
    let(:post) { create(:post, author: author) }
    let(:followers) { create_list(:user, 5) }

    before do
      followers.each { |f| f.follow(author) }
    end

    it 'creates feed entries for all followers' do
      expect {
        FeedEntry.bulk_insert_for_post(post, followers.map(&:id))
      }.to change { FeedEntry.count }.by(5)
    end

    it 'does not create entries if follower_ids is empty' do
      expect {
        FeedEntry.bulk_insert_for_post(post, [])
      }.not_to change { FeedEntry.count }
    end

    it 'handles duplicate entries gracefully' do
      FeedEntry.bulk_insert_for_post(post, followers.map(&:id))

      # Try to insert again (should not raise error)
      expect {
        FeedEntry.bulk_insert_for_post(post, followers.map(&:id))
      }.not_to raise_error

      # Should still have only 5 entries
      expect(FeedEntry.where(post_id: post.id).count).to eq(5)
    end

    it 'inserts entries in batches of 1000' do
      large_follower_list = create_list(:user, 2500)
      large_follower_list.each { |f| f.follow(author) }

      expect {
        FeedEntry.bulk_insert_for_post(post, large_follower_list.map(&:id))
      }.to change { FeedEntry.count }.by(2500)
    end
  end

  describe '.remove_for_user_from_author' do
    let(:user) { create(:user) }
    let(:author1) { create(:user) }
    let(:author2) { create(:user) }
    let(:post1) { create(:post, author: author1) }
    let(:post2) { create(:post, author: author1) }
    let(:post3) { create(:post, author: author2) }

    before do
      FeedEntry.create!(user: user, post: post1, author: author1, created_at: post1.created_at)
      FeedEntry.create!(user: user, post: post2, author: author1, created_at: post2.created_at)
      FeedEntry.create!(user: user, post: post3, author: author2, created_at: post3.created_at)
    end

    it 'removes all feed entries for a user from a specific author' do
      expect {
        FeedEntry.remove_for_user_from_author(user.id, author1.id)
      }.to change { FeedEntry.count }.by(-2)

      expect(FeedEntry.where(user_id: user.id, author_id: author1.id).count).to eq(0)
      expect(FeedEntry.where(user_id: user.id, author_id: author2.id).count).to eq(1)
    end
  end

  describe '.remove_for_post' do
    let(:user1) { create(:user) }
    let(:user2) { create(:user) }
    let(:author) { create(:user) }
    let(:post) { create(:post, author: author) }

    before do
      FeedEntry.create!(user: user1, post: post, author: author, created_at: post.created_at)
      FeedEntry.create!(user: user2, post: post, author: author, created_at: post.created_at)
    end

    it 'removes all feed entries for a specific post' do
      expect {
        FeedEntry.remove_for_post(post.id)
      }.to change { FeedEntry.count }.by(-2)

      expect(FeedEntry.where(post_id: post.id).count).to eq(0)
    end
  end
end

