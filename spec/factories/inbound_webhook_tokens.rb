FactoryBot.define do
  factory :inbound_webhook_token do
    association :admin_user
    enabled { true }
  end
end
