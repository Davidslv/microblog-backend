require 'rails_helper'

RSpec.describe Post, type: :model do
  describe 'associations' do
    it { should belong_to(:author).class_name('User').optional }
    it { should belong_to(:parent).class_name('Post').optional }
    it { should have_many(:replies).class_name('Post').with_foreign_key('parent_id').dependent(:nullify) }
  end

  describe 'validations' do
    subject { build(:post) }

    it { should validate_presence_of(:content) }
    it { should validate_length_of(:content).is_at_most(200) }
  end

  describe 'scopes' do
    let!(:post1) { create(:post, created_at: 3.days.ago) }
    let!(:post2) { create(:post, created_at: 2.days.ago) }
    let!(:post3) { create(:post, created_at: 1.day.ago) }
    let!(:reply1) { create(:post, :reply, parent: post1, created_at: 1.hour.ago) }
    let!(:reply2) { create(:post, :reply, parent: post2, created_at: 2.hours.ago) }

    describe '.timeline' do
      it 'orders posts by created_at descending' do
        timeline_ids = Post.timeline.pluck(:id)
        # Should include all posts, newest first
        expect(timeline_ids.first).to eq(reply1.id) # newest
        expect(timeline_ids).to include(post1.id, post2.id, post3.id, reply1.id, reply2.id)
      end
    end

    describe '.top_level' do
      it 'returns only posts without a parent' do
        expect(Post.top_level).to contain_exactly(post1, post2, post3)
      end

      it 'excludes replies' do
        expect(Post.top_level).not_to include(reply1, reply2)
      end
    end

    describe '.replies' do
      it 'returns only posts with a parent' do
        expect(Post.replies).to contain_exactly(reply1, reply2)
      end

      it 'excludes top-level posts' do
        expect(Post.replies).not_to include(post1, post2, post3)
      end
    end
  end

  describe '#reply?' do
    let(:post) { create(:post) }
    let(:reply) { create(:post, :reply) }

    it 'returns true for posts with a parent' do
      expect(reply.reply?).to be true
    end

    it 'returns false for top-level posts' do
      expect(post.reply?).to be false
    end
  end

  describe '#author_name' do
    let(:user) { create(:user, username: 'testuser') }
    let(:post) { create(:post, author: user) }

    context 'when author exists' do
      it 'returns the author username' do
        expect(post.author_name).to eq('testuser')
      end
    end

    context 'when author is deleted (nil)' do
      before { post.update(author_id: nil) }

      it 'returns "Deleted User"' do
        expect(post.author_name).to eq('Deleted User')
      end
    end
  end

  describe 'content length validation' do
    it 'allows content up to 200 characters' do
      post = build(:post, content: 'a' * 200)
      expect(post).to be_valid
    end

    it 'rejects content over 200 characters' do
      post = build(:post, content: 'a' * 201)
      expect(post).not_to be_valid
      expect(post.errors[:content]).to be_present
    end
  end

  describe 'cascade behavior' do
    let(:user) { create(:user) }
    let(:post) { create(:post, author: user) }
    let(:reply) { create(:post, :reply, parent: post) }

    context 'when author is deleted' do
      it 'sets author_id to nil but keeps the post' do
        expect { user.destroy }.to change { post.reload.author_id }.to(nil)
      end

      it 'does not delete the post' do
        expect { user.destroy }.not_to change { Post.count }
      end
    end

    context 'when parent post is deleted' do
      it 'sets parent_id to nil but keeps the reply' do
        expect { post.destroy }.to change { reply.reload.parent_id }.to(nil)
      end

      it 'does not delete the reply' do
        expect { post.destroy }.not_to change { Post.count }
      end
    end
  end

  describe 'fan-out on write' do
    let(:author) { create(:user) }
    let(:follower) { create(:user) }

    before do
      follower.follow(author)
    end

    it 'enqueues FanOutFeedJob when top-level post is created' do
      expect {
        post = author.posts.create!(content: "Test post")
      }.to have_enqueued_job(FanOutFeedJob).with(a_kind_of(Integer))
    end

    it 'does not enqueue job for replies' do
      parent_post = create(:post, author: author)

      expect {
        reply = create(:post, :reply, parent: parent_post, author: author)
      }.not_to have_enqueued_job(FanOutFeedJob)
    end

    it 'creates feed entries for followers when post is created' do
      expect {
        post = author.posts.create!(content: "Test post")
        perform_enqueued_jobs
      }.to change { FeedEntry.where(user_id: follower.id).count }.by(1)
    end

    it 'deletes feed entries when post is deleted' do
      post = create(:post, author: author)
      perform_enqueued_jobs

      feed_entry = FeedEntry.find_by(user_id: follower.id, post_id: post.id)
      expect(feed_entry).to be_present

      expect {
        post.destroy
      }.to change { FeedEntry.where(post_id: post.id).count }.by(-1)
    end
  end
end
