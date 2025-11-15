FactoryBot.define do
  factory :report do
    association :post
    association :reporter, factory: :user
  end
end
