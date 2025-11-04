# FanOutFeedJob
# Background job to fan-out posts to followers' feeds
#
# Purpose:
# When a user creates a post, we need to create FeedEntry records for all their followers.
# This job runs asynchronously to avoid blocking the request.
#
# Performance:
# - For user with 100 followers: ~50-100ms (small batch)
# - For user with 5,000 followers: ~500-1000ms (large batch)
# - Runs in background, so user doesn't wait
#
# Architecture:
# 1. User creates post
# 2. Post is saved to database
# 3. FanOutFeedJob is enqueued
# 4. Job processes followers in batches
# 5. FeedEntry records are created
#
# See: docs/033_FAN_OUT_ON_WRITE_IMPLEMENTATION.md
class FanOutFeedJob < ApplicationJob
  queue_as :default

  # Retry configuration
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(post_id)
    post = Post.find_by(id: post_id)
    return unless post

    # Only fan-out top-level posts (not replies)
    # Replies appear in the post's thread, not in feeds
    return if post.parent_id.present?

    # Only fan-out if post has an author
    return unless post.author_id.present?

    author = post.author
    return unless author

    # Get all followers (we'll process in batches)
    # Use pluck to avoid loading full User objects
    follower_ids = author.followers.pluck(:id)

    return if follower_ids.empty?

    Rails.logger.info "[FanOutFeedJob] Fanning out post #{post.id} to #{follower_ids.size} followers"

    # Bulk insert feed entries
    # This is much more efficient than individual inserts
    FeedEntry.bulk_insert_for_post(post, follower_ids)

    Rails.logger.info "[FanOutFeedJob] Completed fan-out for post #{post.id}"
  rescue => e
    Rails.logger.error "[FanOutFeedJob] Error fanning out post #{post_id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise # Re-raise to trigger retry
  end
end
