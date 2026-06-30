FactoryBot.define do
  factory :access_control_rule do
    tenant { profile&.tenant || admin_user&.tenant || created_by&.tenant || Current.tenant || Tenant.default }
    sequence(:name) { |n| "Regra #{n}" }
    rule_type { "allow_ip" }
    scope_type { "global" }
    ip_value { "127.0.0.1" }
    enabled { true }
  end
end
