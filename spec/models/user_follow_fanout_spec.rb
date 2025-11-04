require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'follow/unfollow with fan-out' do
    let(:follower) { create(:user) }
    let(:followed) { create(:user) }
    let!(:old_post) { create(:post, author: followed, created_at: 10.days.ago) }
    let!(:recent_post1) { create(:post, author: followed, created_at: 5.days.ago) }
    let!(:recent_post2) { create(:post, author: followed, created_at: 3.days.ago) }
    let!(:recent_post3) { create(:post, author: followed, created_at: 1.day.ago) }

    describe '#follow' do
      it 'enqueues BackfillFeedJob when following someone' do
        expect {
          follower.follow(followed)
        }.to have_enqueued_job(BackfillFeedJob).with(follower.id, followed.id)
      end

      it 'creates feed entries for recent posts when following' do
        # old_post + 3 recent posts = 4 total posts
        expect {
          follower.follow(followed)
          perform_enqueued_jobs
        }.to change { FeedEntry.where(user_id: follower.id, author_id: followed.id).count }.by(4)
      end

      it 'only backfills recent posts (last 50)' do
        # Clear existing posts and feed entries for this test to avoid interference
        Post.where(author_id: followed.id).delete_all
        FeedEntry.where(user_id: follower.id, author_id: followed.id).delete_all

        # Create 100 top-level posts with distinct timestamps
        # BackfillFeedJob should only backfill the most recent 50
        100.times do |i|
          create(:post, :top_level, author: followed, created_at: i.hours.ago)
        end

        # Verify we have 100 posts
        total_posts = Post.where(author_id: followed.id, parent_id: nil).count
        expect(total_posts).to eq(100)

        # Manually test the query to ensure it works
        limited_posts = Post.where(author_id: followed.id, parent_id: nil)
                            .order(created_at: :desc)
                            .limit(50)
                            .to_a
        expect(limited_posts.size).to eq(50), "Query should return 50 posts, got #{limited_posts.size}"

        # Now test the actual job
        BackfillFeedJob.perform_now(follower.id, followed.id)

        # Should have at most 50 entries (the most recent 50, out of 100 total)
        entry_count = FeedEntry.where(user_id: follower.id, author_id: followed.id).count
        expect(entry_count).to be <= 50, "Should not create more than 50 entries, got #{entry_count}. Total posts: #{total_posts}"
        expect(entry_count).to eq(50), "Expected exactly 50 entries but got #{entry_count}. Total posts: #{total_posts}"
      end

      it 'does not create duplicate entries if already following' do
        follower.follow(followed)
        perform_enqueued_jobs

        initial_count = FeedEntry.where(user_id: follower.id, author_id: followed.id).count

        # Try to follow again (should fail)
        result = follower.follow(followed)
        expect(result).to be false

        # Count should be unchanged
        expect(FeedEntry.where(user_id: follower.id, author_id: followed.id).count).to eq(initial_count)
      end
    end

    describe '#unfollow' do
      before do
        follower.follow(followed)
        perform_enqueued_jobs
      end

      it 'removes feed entries when unfollowing' do
        expect(FeedEntry.where(user_id: follower.id, author_id: followed.id).count).to be > 0

        expect {
          follower.unfollow(followed)
        }.to change { FeedEntry.where(user_id: follower.id, author_id: followed.id).count }.to(0)
      end

      it 'does not remove entries from other authors' do
        other_author = create(:user)
        other_post = create(:post, author: other_author)
        follower.follow(other_author)
        perform_enqueued_jobs

        other_entries_count = FeedEntry.where(user_id: follower.id, author_id: other_author.id).count

        follower.unfollow(followed)

        # Other author's entries should remain
        expect(FeedEntry.where(user_id: follower.id, author_id: other_author.id).count).to eq(other_entries_count)
      end

      it 'handles unfollowing when not following' do
        follower.unfollow(followed) # Already unfollowed

        result = follower.unfollow(followed)
        expect(result).to be false
      end
    end
  end
end
