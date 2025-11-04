class User < ApplicationRecord
  has_secure_password

  has_many :posts, foreign_key: "author_id", dependent: :nullify
  # Follow associations don't use counter_cache (we manage counters manually via Follow callbacks)
  has_many :active_follows, class_name: "Follow", foreign_key: "follower_id", dependent: :delete_all, counter_cache: false
  has_many :passive_follows, class_name: "Follow", foreign_key: "followed_id", dependent: :delete_all, counter_cache: false
  has_many :following, through: :active_follows, source: :followed
  has_many :followers, through: :passive_follows, source: :follower

  validates :username, presence: true, uniqueness: true, length: { maximum: 50 }
  validates :description, length: { maximum: 120 }, allow_nil: true
  validates :password, length: { minimum: 6 }, allow_blank: true

  def follow(other_user)
    return false if self == other_user
    return false if following?(other_user)

    # Follow model callbacks will update counter caches automatically
    follow_record = active_follows.build(followed_id: other_user.id)
    if follow_record.save
      # Invalidate feed cache when following someone new
      # User's feed will now include posts from the followed user
      Rails.cache.delete_matched("user_feed:#{id}:*")
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

      # Invalidate feed cache when unfollowing
      # User's feed will no longer include posts from the unfollowed user
      Rails.cache.delete_matched("user_feed:#{id}:*")

      true
    else
      false
    end
  end

  def following?(other_user)
    following.include?(other_user)
  end

  def feed_posts
    # Optimized: Use JOIN instead of large IN clause
    # This is much more efficient for users with many follows (2,500+)
    # Instead of: WHERE author_id IN (?, ?, ..., 2506 times)
    # We use: JOIN follows table to get posts from followed users + own posts
    # Note: Caching is handled at the controller level after pagination
    user_id = Post.connection.quote(id)
    Post.joins(
      "LEFT JOIN follows ON posts.author_id = follows.followed_id AND follows.follower_id = #{user_id}"
    ).where(
      "posts.author_id = ? OR follows.followed_id IS NOT NULL",
      id
    ).distinct
  end
end
