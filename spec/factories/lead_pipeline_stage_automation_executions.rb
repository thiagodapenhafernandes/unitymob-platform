FactoryBot.define do
  factory :lead_pipeline_stage_automation_execution do
    tenant { lead_pipeline_stage_automation.tenant }
    lead_pipeline_stage_automation
    lead { association(:lead, tenant: tenant, lead_pipeline_stage: lead_pipeline_stage) }
    lead_pipeline_stage { lead_pipeline_stage_automation.lead_pipeline_stage }
    action_type { lead_pipeline_stage_automation.action_type }
    trigger { lead_pipeline_stage_automation.trigger }
    status { "started" }
    stage_entered_at { 1.day.ago }
    started_at { Time.current }
    metadata { {} }
  end
end
