FactoryBot.define do
  factory :admin_user do
    username { Faker::Internet.unique.username(specifier: 5..20) }
    password { "password123" }
    password_confirmation { "password123" }

    trait :with_password do
      password { "admin123" }
      password_confirmation { "admin123" }
    end
  end
end
