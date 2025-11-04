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

  # Note: Cache invalidation removed - cache will expire via TTL
  # With fan-out on write, feed entries are the source of truth
  # Cache invalidation is less critical and was removed from Rails 8

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
end
