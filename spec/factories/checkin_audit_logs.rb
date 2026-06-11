FactoryBot.define do
  factory :checkin_audit_log do
    action { "created" }
    metadata { {} }
    created_at { Time.current }
  end
end
