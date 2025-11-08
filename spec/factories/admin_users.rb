FactoryBot.define do
  factory :admin_user do
    username { Faker::Internet.unique.username(specifier: 5..20) }
    password { "password123" }
    password_confirmation { "password123" }
  end
end

