FactoryBot.define do
  factory :external_lead_integration do
    tenant { connected_by_admin_user&.tenant || Current.tenant || Tenant.default }
    enabled { true }
    status { "connected" }
    access_token { "lead-migration-token" }
    webhook_token { SecureRandom.urlsafe_base64(32) }
    company_id { "company-1" }
    company_name { "Conta externa" }
    sellers_payload { [] }
    tags_payload { [] }
    seller_mappings { {} }
    sync_status { "idle" }
    association :connected_by_admin_user, factory: :admin_user
  end
end
