require 'rails_helper'

RSpec.describe User, type: :model do
  describe '#feed_posts' do
    let(:user) { create(:user) }
    let(:author1) { create(:user) }
    let(:author2) { create(:user) }
    let(:post1) { create(:post, author: author1, created_at: 3.days.ago) }
    let(:post2) { create(:post, author: author2, created_at: 2.days.ago) }
    let(:post3) { create(:post, author: author1, created_at: 1.day.ago) }
    let(:own_post) { create(:post, author: user, created_at: 4.days.ago) }

    context 'when feed entries exist (fan-out enabled)' do
      before do
        # Create feed entries for user
        FeedEntry.create!(user: user, post: post1, author: author1, created_at: post1.created_at)
        FeedEntry.create!(user: user, post: post2, author: author2, created_at: post2.created_at)
        FeedEntry.create!(user: user, post: post3, author: author1, created_at: post3.created_at)
        FeedEntry.create!(user: user, post: own_post, author: user, created_at: own_post.created_at)
      end

      it 'returns posts from feed entries' do
        posts = user.feed_posts
        expect(posts).to include(post1, post2, post3, own_post)
      end

      it 'orders posts by created_at descending' do
        posts = user.feed_posts.to_a
        expect(posts.first).to eq(post3) # newest
        expect(posts.last).to eq(own_post) # oldest
      end

      it 'does not include posts not in feed entries' do
        other_post = create(:post, author: author1)
        posts = user.feed_posts
        expect(posts).not_to include(other_post)
      end

      it 'uses the fast path query (feed entries)' do
        sql = user.feed_posts.to_sql
        expect(sql).to include('feed_entries')
      end
    end

    context 'when feed entries do not exist (fallback mode)' do
      before do
        # User follows authors
        user.follow(author1)
        user.follow(author2)
      end

      it 'falls back to JOIN-based query' do
        sql = user.feed_posts.to_sql
        expect(sql).to include('follows')
        expect(sql).not_to include('feed_entries')
      end

      it 'returns posts from followed users' do
        posts = user.feed_posts
        expect(posts).to include(post1, post2, post3)
      end

      it 'includes own posts' do
        posts = user.feed_posts
        expect(posts).to include(own_post)
      end
    end

    context 'when user has no feed entries and no follows' do
      it 'returns only own posts' do
        posts = user.feed_posts
        expect(posts).to include(own_post)
        expect(posts).not_to include(post1, post2, post3)
      end
    end
  end

  describe 'fan-out integration' do
    let(:user) { create(:user) }
    let(:author) { create(:user) }

    before do
      user.follow(author)
    end

    it 'creates feed entries when post is created' do
      expect {
        post = author.posts.create!(content: "Test post")
        # Wait for job to process (in test environment, jobs run synchronously)
        perform_enqueued_jobs
      }.to change { FeedEntry.where(user_id: user.id).count }.by(1)
    end

    it 'creates feed entries via FanOutFeedJob' do
      post = create(:post, author: author)

      expect {
        FanOutFeedJob.perform_now(post.id)
      }.to change { FeedEntry.where(user_id: user.id).count }.by(1)
    end

    it 'does not create feed entries for replies' do
      parent_post = create(:post, author: author)
      reply = create(:post, :reply, parent: parent_post, author: author)

      expect {
        FanOutFeedJob.perform_now(reply.id)
      }.not_to change { FeedEntry.count }
    end
  end
end

