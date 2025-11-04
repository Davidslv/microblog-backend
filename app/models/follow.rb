class Follow < ApplicationRecord
  belongs_to :follower, class_name: "User"
  belongs_to :followed, class_name: "User"

  validates :follower_id, uniqueness: { scope: :followed_id, message: "already following this user" }
  validate :cannot_follow_self

  # Update counter caches when follow is created/destroyed
  after_create :increment_counters
  after_destroy :decrement_counters

  private

  def cannot_follow_self
    errors.add(:followed_id, "cannot follow yourself") if follower_id == followed_id
  end

  def increment_counters
    User.increment_counter(:following_count, follower_id)
    User.increment_counter(:followers_count, followed_id)
  end

  def decrement_counters
    User.decrement_counter(:following_count, follower_id)
    User.decrement_counter(:followers_count, followed_id)
  end
end
