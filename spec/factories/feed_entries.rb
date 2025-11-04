FactoryBot.define do
  factory :feed_entry do
    association :user
    association :post
    association :author, factory: :user

    # Set created_at to match post creation time
    created_at { post.created_at }
  end
end
