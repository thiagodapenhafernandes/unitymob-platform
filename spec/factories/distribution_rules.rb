FactoryBot.define do
  factory :distribution_rule do
    tenant { Current.tenant || Tenant.default }
    sequence(:name) { |n| "Regra #{n}" }
    business_type { :ambos }
    distribution_mode { :rotary }
    active { true }
    source_site { true }
    source_meta { false }
    source_portal { false }
    source_webhook { false }
    pocket_active { false }
    represamento_active { false }
    require_active_checkin { false }
    require_inside_radius { false }
    require_active_shift { false }
    exclude_suspicious_checkins { true }
  end

  factory :distribution_rule_agent do
    association :distribution_rule
    association :admin_user
    weight { 1 }
  end
end
