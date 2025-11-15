class Report < ApplicationRecord
  belongs_to :post
  belongs_to :reporter, class_name: "User"

  validates :post_id, uniqueness: { scope: :reporter_id, message: "has already been reported by this user" }

  scope :for_post, ->(post) { where(post: post) }
  scope :by_reporter, ->(reporter) { where(reporter: reporter) }
  scope :recent, -> { order(created_at: :desc) }
end
