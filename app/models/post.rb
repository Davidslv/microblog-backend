class Post < ApplicationRecord
  belongs_to :author, class_name: "User", optional: true, counter_cache: :posts_count
  belongs_to :parent, class_name: "Post", optional: true
  has_many :replies, class_name: "Post", foreign_key: "parent_id", dependent: :nullify

  validates :content, presence: true, length: { maximum: 200 }

  scope :timeline, -> { order(created_at: :desc) }
  scope :top_level, -> { where(parent_id: nil) }
  scope :replies, -> { where.not(parent_id: nil) }

  def reply?
    parent_id.present?
  end

  def author_name
    author&.username || "Deleted User"
  end
end

