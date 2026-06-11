FactoryBot.define do
  factory :lead_audit_log do
    association :lead
    association :admin_user
    action { "updated" }
    source { "admin" }
    changed_fields { ["status"] }
    changeset { { "status" => { "before" => "Novo", "after" => "Em Atendimento" } } }
    metadata { {} }
    ip { "127.0.0.1" }
    user_agent { "RSpec" }
    created_at { Time.current }
  end
end
