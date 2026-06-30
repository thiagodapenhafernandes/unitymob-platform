FactoryBot.define do
  factory :checkin_audit_log do
    tenant { Current.tenant || Tenant.default }
    action { "created" }
    metadata { {} }
    created_at { Time.current }
  end
end
