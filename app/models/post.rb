class Post < ApplicationRecord
  belongs_to :author, class_name: "User", optional: true, counter_cache: :posts_count
  belongs_to :parent, class_name: "Post", optional: true
  has_many :replies, class_name: "Post", foreign_key: "parent_id", dependent: :nullify
  has_many :feed_entries, dependent: :delete_all # Fan-out entries are deleted when post is deleted

  validates :content, presence: true, length: { maximum: 200 }

  scope :timeline, -> { order(created_at: :desc) }
  scope :top_level, -> { where(parent_id: nil) }
  scope :replies, -> { where.not(parent_id: nil) }

  # Fan-out on write: Create feed entries for all followers when post is created
  # This enables fast feed queries (5-20ms vs 50-200ms)
  after_create :fan_out_to_followers

  # Invalidate caches when posts are created (kept for backward compatibility)
  after_create :invalidate_follower_feeds
  after_create :invalidate_public_posts_cache

  def reply?
    parent_id.present?
  end

  def author_name
    author&.username || "Deleted User"
  end

  private

  def fan_out_to_followers
    # Only fan-out top-level posts (not replies)
    # Replies appear in the post's thread, not in feeds
    return if parent_id.present?

    # Only fan-out if post has an author
    return unless author_id.present?

    # Queue background job to create feed entries for all followers
    # This runs asynchronously so it doesn't block the request
    FanOutFeedJob.perform_later(id)
  end

  def invalidate_follower_feeds
    # Invalidate feed caches for all followers of the post author
    # Use background job to avoid blocking the request
    return unless author.present?

    # Queue background job for large follower counts
    if author.followers_count >= 100
      InvalidateFeedCacheJob.perform_later(author_id) if defined?(InvalidateFeedCacheJob)
    end

    # Invalidate immediately for small follower counts (synchronous for < 100 followers)
    if author.followers_count < 100
      author.followers.find_each do |follower|
        # Invalidate all cursor variations of feed cache
        Rails.cache.delete_matched("user_feed:#{follower.id}:*")
      end
    end
  end

  def invalidate_public_posts_cache
    # Invalidate public posts cache when new post is created
    # Use delete_matched to clear all cursor variations
    Rails.cache.delete_matched("public_posts:*")

    # Also invalidate author's own posts cache
    if author_id.present?
      Rails.cache.delete_matched("user_posts:#{author_id}:*")
    end
  end
end

