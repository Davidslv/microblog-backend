class User < ApplicationRecord
  has_secure_password

  has_many :posts, foreign_key: "author_id", dependent: :nullify
  # Follow associations don't use counter_cache (we manage counters manually via Follow callbacks)
  has_many :active_follows, class_name: "Follow", foreign_key: "follower_id", dependent: :delete_all, counter_cache: false
  has_many :passive_follows, class_name: "Follow", foreign_key: "followed_id", dependent: :delete_all, counter_cache: false
  has_many :following, through: :active_follows, source: :followed
  has_many :followers, through: :passive_follows, source: :follower
  # Fan-out on write: Feed entries for this user's feed (pre-computed feed posts)
  has_many :feed_entries, dependent: :delete_all

  validates :username, presence: true, uniqueness: true, length: { maximum: 50 }
  validates :description, length: { maximum: 120 }, allow_nil: true
  validates :password, length: { minimum: 6 }, allow_blank: true

  def follow(other_user)
    return false if self == other_user
    return false if following?(other_user)

    # Follow model callbacks will update counter caches automatically
    follow_record = active_follows.build(followed_id: other_user.id)
    if follow_record.save
      # Fan-out on write: Backfill recent posts from the followed user
      # This ensures the new follower sees posts from the person they just followed
      BackfillFeedJob.perform_later(id, other_user.id)

      # Note: Cache invalidation removed - cache will expire via TTL
      # Feed entries are the source of truth, cache is just for performance
      true
    else
      false
    end
  end

  def unfollow(other_user)
    # Use delete_all with WHERE clause to avoid composite key issues
    # Manually update counter caches since delete_all doesn't trigger callbacks
    deleted_count = Follow.where(follower_id: id, followed_id: other_user.id).delete_all
    if deleted_count > 0
      # Update counter caches
      decrement!(:following_count)
      other_user.decrement!(:followers_count)

      # Fan-out on write: Remove feed entries from the unfollowed user
      # This ensures posts from this user no longer appear in the feed
      FeedEntry.remove_for_user_from_author(id, other_user.id)

      # Note: Cache invalidation removed - cache will expire via TTL
      # Feed entries are already removed above, so feed queries will be correct

      true
    else
      false
    end
  end

  def following?(other_user)
    following.include?(other_user)
  end

  def feed_posts
    # Fan-out on write: Use pre-computed feed entries for fast queries
    # This is 10-40x faster than the JOIN-based approach (5-20ms vs 50-200ms)
    #
    # Strategy:
    # 1. Check if feed entries exist for this user (fan-out is enabled)
    # 2. If yes, use feed entries (fast path)
    # 3. If no, fall back to JOIN-based query (during migration or for users without entries)
    #
    # See: docs/033_FAN_OUT_ON_WRITE_IMPLEMENTATION.md

    if FeedEntry.exists?(user_id: id)
      # Fast path: Use pre-computed feed entries
      # Query: SELECT posts.* FROM posts
      #        INNER JOIN feed_entries ON posts.id = feed_entries.post_id
      #        WHERE feed_entries.user_id = ?
      #        ORDER BY feed_entries.created_at DESC
      #
      # This is O(log(N)) where N = number of feed entries, vs O(F × log(P)) for JOIN approach
      # Note: We select posts.* explicitly and order by feed_entries.created_at
      # PostgreSQL requires ORDER BY columns in SELECT when using DISTINCT, so we use a subquery approach
      Post.joins("INNER JOIN feed_entries ON posts.id = feed_entries.post_id")
          .where("feed_entries.user_id = ?", id)
          .select("posts.*, feed_entries.created_at AS feed_entry_created_at")
          .order("feed_entries.created_at DESC")
          .distinct
    else
      # Fallback: Use JOIN-based query (for backward compatibility during migration)
      # This is slower but ensures the feed still works during the transition
      user_id = Post.connection.quote(id)
      Post.joins(
        "LEFT JOIN follows ON posts.author_id = follows.followed_id AND follows.follower_id = #{user_id}"
      ).where(
        "posts.author_id = ? OR follows.followed_id IS NOT NULL",
        id
      ).distinct
    end
  end

  def admin?
    # Check if there's a corresponding AdminUser with matching username
    AdminUser.exists?(username: username)
  end
end
