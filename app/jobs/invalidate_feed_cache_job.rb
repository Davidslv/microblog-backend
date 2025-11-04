# Background job to invalidate feed caches for all followers
# This prevents blocking the request when a user has many followers
class InvalidateFeedCacheJob < ApplicationJob
  queue_as :default

  def perform(author_id)
    author = User.find_by(id: author_id)
    return unless author

    # Invalidate feed caches for all followers
    # Process in batches to avoid memory issues
    author.followers.find_in_batches(batch_size: 1000) do |batch|
      batch.each do |follower|
        # Invalidate all cursor variations of feed cache
        Rails.cache.delete_matched("user_feed:#{follower.id}:*")
      end
    end
  end
end

