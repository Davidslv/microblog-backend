class User < ApplicationRecord
  has_secure_password

  has_many :posts, foreign_key: 'author_id', dependent: :nullify
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
    follow_record.save
  end

  def unfollow(other_user)
    active_follows.where(followed_id: other_user.id).delete_all > 0
  end

  def following?(other_user)
    following.include?(other_user)
  end

  def feed_posts
    following_ids = following.pluck(:id)
    Post.where(author_id: [id] + following_ids)
  end
end

