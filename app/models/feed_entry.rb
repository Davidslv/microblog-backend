# FeedEntry Model
# Represents a pre-computed feed entry for fan-out on write architecture
#
# Purpose:
# Instead of querying posts + follows tables on every feed request (slow),
# we pre-compute feed entries when posts are created. Each entry represents
# a post that should appear in a user's feed.
#
# Architecture:
# - When User A creates a post, we create FeedEntry records for all of A's followers
# - When User B requests their feed, we simply query FeedEntry.where(user_id: B.id)
# - This is 10-40x faster than the JOIN-based approach
#
# See: docs/033_FAN_OUT_ON_WRITE_IMPLEMENTATION.md
class FeedEntry < ApplicationRecord
  belongs_to :user
  belongs_to :post
  belongs_to :author, class_name: "User"

  # Validations
  validates :user_id, presence: true
  validates :post_id, presence: true
  validates :author_id, presence: true
  validates :created_at, presence: true

  # Ensure uniqueness: a post should appear only once per user's feed
  validates :user_id, uniqueness: { scope: :post_id, message: "feed entry already exists for this post" }

  # Scopes for common queries
  scope :for_user, ->(user_id) { where(user_id: user_id) }
  scope :from_author, ->(author_id) { where(author_id: author_id) }
  scope :recent, -> { order(created_at: :desc) }
  scope :old, -> { where("created_at < ?", 30.days.ago) }

  # Class methods for bulk operations

  # Bulk insert feed entries (used by FanOutFeedJob)
  # This is much more efficient than individual inserts
  def self.bulk_insert_for_post(post, follower_ids)
    return if follower_ids.empty?

    # Build entries array
    entries = follower_ids.map do |follower_id|
      {
        user_id: follower_id,
        post_id: post.id,
        author_id: post.author_id,
        created_at: post.created_at,
        updated_at: post.created_at
      }
    end

    # Insert in batches to avoid memory issues
    entries.each_slice(1000) do |batch|
      insert_all(batch) if batch.any?
    rescue ActiveRecord::RecordNotUnique
      # Ignore duplicates - entry already exists
      # This can happen if job is retried or run multiple times
      Rails.logger.warn "[FeedEntry] Duplicate entry skipped for post #{post.id}"
    end
  end

  # Remove all feed entries for a user from a specific author
  # Used when user unfollows someone
  def self.remove_for_user_from_author(user_id, author_id)
    where(user_id: user_id, author_id: author_id).delete_all
  end

  # Remove all feed entries for a specific post
  # Used when post is deleted
  def self.remove_for_post(post_id)
    where(post_id: post_id).delete_all
  end
end
