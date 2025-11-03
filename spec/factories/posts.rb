FactoryBot.define do
  factory :post do
    association :author, factory: :user
    content { Faker::Lorem.sentence(word_count: 10) }

    trait :with_long_content do
      content { "a" * 200 } # Max length
    end

    trait :reply do
      association :parent, factory: :post
    end

    trait :top_level do
      parent { nil }
    end
  end
end

