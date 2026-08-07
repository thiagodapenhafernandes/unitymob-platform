FactoryBot.define do
  factory :lead do
    tenant { Current.tenant || Tenant.default }
    name { Faker::Name.name }
    phone { Faker::PhoneNumber.cell_phone }
    email { Faker::Internet.email }
    origin { "site" }
    status { :novo }
    lead_pipeline { LeadPipeline.ensure_default!(tenant:) if defined?(LeadPipeline) }
    lead_pipeline_stage { lead_pipeline&.default_stage }
  end
end
