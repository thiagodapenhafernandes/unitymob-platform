FactoryBot.define do
  factory :lead_pipeline do
    tenant { Current.tenant || Tenant.default }
    sequence(:name) { |n| "Funil #{n}" }
    kind { "custom" }
    active { true }
    default_general { false }
    default_for_sale { false }
    default_for_rental { false }
  end

  factory :lead_pipeline_stage do
    association :lead_pipeline
    tenant { lead_pipeline.tenant }
    sequence(:name) { |n| "Etapa #{n}" }
    stage_type { "open" }
    active { true }
  end

  factory :lead_pipeline_stage_automation do
    association :lead_pipeline_stage
    tenant { lead_pipeline_stage.tenant }
    auto_advance_to_stage { association(:lead_pipeline_stage, tenant: tenant, lead_pipeline: lead_pipeline_stage.lead_pipeline) }
    trigger { "stage_duration" }
    after_amount { 2 }
    after_unit { "days" }
    active { true }
  end
end
