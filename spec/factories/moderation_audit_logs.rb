FactoryBot.define do
  factory :moderation_audit_log do
    association :post
    action { 'report' }
    association :user

    trait :redaction do
      action { 'redact' }
      metadata { { reason: 'auto' } }
    end

    trait :unredaction do
      action { 'unredact' }
    end
  end
end
