FactoryBot.define do
  factory :access_control_rule do
    sequence(:name) { |n| "Regra #{n}" }
    rule_type { "allow_ip" }
    scope_type { "global" }
    ip_value { "127.0.0.1" }
    enabled { true }
  end
end
