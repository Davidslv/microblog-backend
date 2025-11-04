require 'rails_helper'

RSpec.describe BackfillFeedJob, type: :job do
  describe '#perform' do
    let(:follower) { create(:user) }
    let(:followed) { create(:user) }
    let!(:old_post) { create(:post, author: followed, created_at: 60.days.ago) }
    let!(:recent_post1) { create(:post, author: followed, created_at: 5.days.ago) }
    let!(:recent_post2) { create(:post, author: followed, created_at: 3.days.ago) }
    let!(:recent_post3) { create(:post, author: followed, created_at: 1.day.ago) }
    let!(:reply) { create(:post, :reply, parent: recent_post1, author: followed) }

    it 'backfills recent posts from followed user' do
      # Note: old_post is older and won't be included in backfill (last 50)
      # So we expect 3 entries (recent_post1, recent_post2, recent_post3)
      # But BackfillFeedJob gets last 50 posts ordered by created_at DESC
      # So it will include old_post if it's in the last 50
      initial_count = FeedEntry.where(user_id: follower.id, author_id: followed.id).count

      BackfillFeedJob.perform_now(follower.id, followed.id)

      final_count = FeedEntry.where(user_id: follower.id, author_id: followed.id).count
      expect(final_count - initial_count).to eq(4) # old_post + 3 recent posts (all are in last 50)
    end

    it 'only backfills top-level posts (not replies)' do
      BackfillFeedJob.perform_now(follower.id, followed.id)

      entry_post_ids = FeedEntry.where(user_id: follower.id).pluck(:post_id)
      expect(entry_post_ids).to include(recent_post1.id, recent_post2.id, recent_post3.id)
      expect(entry_post_ids).not_to include(reply.id)
    end

    it 'only backfills last 50 posts' do
      # Create 60 posts
      create_list(:post, 60, author: followed, created_at: 10.days.ago)

      BackfillFeedJob.perform_now(follower.id, followed.id)

      # Should have 50 entries (the most recent 50)
      expect(FeedEntry.where(user_id: follower.id).count).to eq(50)
    end

    it 'creates correct feed entries' do
      BackfillFeedJob.perform_now(follower.id, followed.id)

      entry = FeedEntry.find_by(user_id: follower.id, post_id: recent_post1.id)
      expect(entry).to be_present
      expect(entry.author_id).to eq(followed.id)
      expect(entry.created_at).to be_within(1.second).of(recent_post1.created_at)
    end

    it 'handles non-existent users gracefully' do
      expect {
        BackfillFeedJob.perform_now(999999, followed.id)
        BackfillFeedJob.perform_now(follower.id, 999999)
      }.not_to raise_error
    end

    it 'handles users with no posts gracefully' do
      user_without_posts = create(:user)

      expect {
        BackfillFeedJob.perform_now(follower.id, user_without_posts.id)
      }.not_to raise_error

      expect(FeedEntry.where(user_id: follower.id).count).to eq(0)
    end

    it 'handles duplicate entries gracefully' do
      # Run backfill twice
      BackfillFeedJob.perform_now(follower.id, followed.id)
      initial_count = FeedEntry.where(user_id: follower.id).count

      # Run again (should not create duplicates)
      BackfillFeedJob.perform_now(follower.id, followed.id)

      # Count should be the same
      expect(FeedEntry.where(user_id: follower.id).count).to eq(initial_count)
    end
  end
end

