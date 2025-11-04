class User < ApplicationRecord
  has_secure_password

  has_many :posts, foreign_key: 'author_id', dependent: :nullify, counter_cache: true
  has_many :active_follows, class_name: 'Follow', foreign_key: 'follower_id', dependent: :delete_all
  has_many :passive_follows, class_name: 'Follow', foreign_key: 'followed_id', dependent: :delete_all
  has_many :following, through: :active_follows, source: :followed
  has_many :followers, through: :passive_follows, source: :follower

  validates :username, presence: true, uniqueness: true, length: { maximum: 50 }
  validates :description, length: { maximum: 120 }, allow_nil: true
  validates :password, length: { minimum: 6 }, allow_blank: true

  def follow(other_user)
    return false if self == other_user
    return false if following?(other_user)

    follow_record = active_follows.build(followed_id: other_user.id)
    if follow_record.save
      # Update counter caches
      increment!(:following_count)
      other_user.increment!(:followers_count)
      true
    else
      false
    end
  end

  def unfollow(other_user)
    deleted = active_follows.where(followed_id: other_user.id).delete_all
    if deleted > 0
      # Update counter caches
      decrement!(:following_count)
      other_user.decrement!(:followers_count)
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
    user_id = Post.connection.quote(id)
    Post.joins(
      "LEFT JOIN follows ON posts.author_id = follows.followed_id AND follows.follower_id = #{user_id}"
    ).where(
      "posts.author_id = ? OR follows.followed_id IS NOT NULL",
      id
    ).distinct
  end
end

