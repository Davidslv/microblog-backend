# BackfillFeedJob
# Background job to backfill feed entries when a user follows someone
#
# Purpose:
# When User A follows User B, we need to add User B's recent posts to User A's feed.
# This ensures the new follower sees posts from the person they just followed.
#
# Why Backfill?
# - When User A follows User B, User B's existing posts aren't in User A's feed yet
# - We only backfill recent posts (last 50) to avoid overwhelming the feed
# - Older posts will appear if they're still relevant, but we don't flood the feed
#
# Performance:
# - Backfills last 50 posts from followed user
# - Takes ~50-200ms depending on number of posts
# - Runs asynchronously, so follow action is fast
#
# See: docs/033_FAN_OUT_ON_WRITE_IMPLEMENTATION.md
class BackfillFeedJob < ApplicationJob
  queue_as :default

  # Retry configuration
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(follower_id, followed_id)
    follower = User.find_by(id: follower_id)
    followed = User.find_by(id: followed_id)

    return unless follower && followed

    Rails.logger.info "[BackfillFeedJob] Backfilling feed for user #{follower_id} from user #{followed_id}"

    # Get recent top-level posts from followed user (last 50)
    # We limit to 50 to avoid overwhelming the feed with old posts
    # Use .limit(50).to_a to ensure we only get 50 posts
    posts = Post.where(author_id: followed_id, parent_id: nil)
                .order(created_at: :desc)
                .limit(50)
                .to_a

    return if posts.empty?

    # Double-check we only have 50 posts
    posts = posts.first(50)

    Rails.logger.debug "[BackfillFeedJob] Processing #{posts.size} posts for user #{follower_id}"

    # Create feed entries for these posts
    entries = posts.map do |post|
      {
        user_id: follower_id,
        post_id: post.id,
        author_id: followed_id,
        created_at: post.created_at,
        updated_at: post.created_at
      }
    end

    # Bulk insert in batches
    entries.each_slice(1000) do |batch|
      FeedEntry.insert_all(batch) if batch.any?
    rescue ActiveRecord::RecordNotUnique
      # Ignore duplicates - entry may already exist
      Rails.logger.warn "[BackfillFeedJob] Duplicate entry skipped"
    end

    Rails.logger.info "[BackfillFeedJob] Backfilled #{entries.size} posts for user #{follower_id}"
  rescue => e
    Rails.logger.error "[BackfillFeedJob] Error backfilling feed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise # Re-raise to trigger retry
  end
end

