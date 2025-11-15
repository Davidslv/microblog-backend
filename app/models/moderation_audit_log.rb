class ModerationAuditLog < ApplicationRecord
  belongs_to :post
  belongs_to :user, optional: true
  belongs_to :admin, class_name: "User", optional: true

  validates :action, presence: true
  validates :post, presence: true

  scope :for_post, ->(post) { where(post: post) }
  scope :by_action, ->(action) { where(action: action) }
  scope :recent, -> { order(created_at: :desc) }
end
