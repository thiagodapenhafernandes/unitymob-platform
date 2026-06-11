FactoryBot.define do
  factory :data_export_audit_log do
    association :admin_user
    export_type { "csv_export" }
    resource_name { "habitations" }
    format { "csv" }
    record_count { 1 }
    selected_count { 0 }
    filters { {} }
    fields { ["codigo"] }
    metadata { {} }
    ip { "127.0.0.1" }
    user_agent { "RSpec" }
    created_at { Time.current }
  end
end
