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
    color { "#365f8f" }
    active { true }
  end

  factory :lead_pipeline_stage_automation do
    association :lead_pipeline_stage
    tenant { lead_pipeline_stage.tenant }
    auto_advance_to_stage { association(:lead_pipeline_stage, tenant: tenant, lead_pipeline: lead_pipeline_stage.lead_pipeline) }
    trigger { "stage_duration" }
    after_amount { 2 }
    after_unit { "days" }
    action_type { "move_stage" }
    action_config { {} }
    active { true }
  end

  factory :lead_pipeline_stage_policy do
    association :lead_pipeline_stage
    tenant { lead_pipeline_stage.tenant }
    visible_to_roles { LeadPipelineStagePolicy::DEFAULT_VISIBLE_ROLES }
    qualification_options { LeadPipelineStagePolicy::DEFAULT_QUALIFICATION_OPTIONS }
    divergence_queue_enabled { false }
    qualification_enabled { false }
    allowed_archive_reason_ids { [] }
    settings { {} }
  end

  factory :lead_pipeline_stage_transition do
    association :lead_pipeline_stage
    tenant { lead_pipeline_stage.tenant }
    next_stage { association(:lead_pipeline_stage, tenant: tenant, lead_pipeline: lead_pipeline_stage.lead_pipeline) }
  end
end
