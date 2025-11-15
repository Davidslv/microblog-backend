FactoryBot.define do
  factory :user do
    username { Faker::Internet.unique.username(specifier: 5..20) }
    description { Faker::Lorem.sentence(word_count: 10) }
    password { "password123" }
    password_confirmation { "password123" }

    trait :with_posts do
      after(:create) do |user|
        create_list(:post, 3, author: user)
      end
    end

    trait :with_description do
      description { Faker::Lorem.sentence(word_count: 15) }
    end

    trait :without_description do
      description { nil }
    end

    trait :admin do
      after(:create) do |user|
        # Create corresponding AdminUser with matching username
        create(:admin_user, username: user.username)
      end
    end
  end
end
