require "rails_helper"

RSpec.describe Leads::PipelineStageAutoAdvanceJob, type: :job do
  let(:tenant) { Tenant.default }
  let(:pipeline) { create(:lead_pipeline, tenant: tenant) }
  let(:source_stage) { create(:lead_pipeline_stage, tenant: tenant, lead_pipeline: pipeline, name: "Sem retorno") }
  let(:destination_stage) { create(:lead_pipeline_stage, tenant: tenant, lead_pipeline: pipeline, name: "Nutrição") }

  it "executa apenas quando o intervalo configurado venceu" do
    setting = LeadSetting.instance(tenant: tenant)
    setting.update!(stage_automation_sweep_interval_minutes: 15, stage_automation_last_swept_at: 20.minutes.ago)
    create(:lead_pipeline_stage_automation, lead_pipeline_stage: source_stage, tenant: tenant, auto_advance_to_stage: destination_stage)
    lead = create(:lead, tenant: tenant, lead_pipeline: pipeline, lead_pipeline_stage: source_stage, status: source_stage.name)
    create(
      :lead_audit_log,
      lead: lead,
      tenant: tenant,
      action: "status_changed",
      source: "admin",
      changeset: { status: { before: "Novo", after: source_stage.name } },
      created_at: 3.days.ago
    )

    expect {
      described_class.perform_now
    }.to change { lead.reload.lead_pipeline_stage_id }.from(source_stage.id).to(destination_stage.id)
    expect(setting.reload.stage_automation_last_swept_at).to be_present
  end

  it "ignora conta que ainda nao atingiu o intervalo minimo" do
    setting = LeadSetting.instance(tenant: tenant)
    setting.update!(stage_automation_sweep_interval_minutes: 15, stage_automation_last_swept_at: 5.minutes.ago)
    create(:lead_pipeline_stage_automation, lead_pipeline_stage: source_stage, tenant: tenant, auto_advance_to_stage: destination_stage)
    lead = create(:lead, tenant: tenant, lead_pipeline: pipeline, lead_pipeline_stage: source_stage, status: source_stage.name)
    create(
      :lead_audit_log,
      lead: lead,
      tenant: tenant,
      action: "status_changed",
      source: "admin",
      changeset: { status: { before: "Novo", after: source_stage.name } },
      created_at: 3.days.ago
    )

    expect {
      described_class.perform_now
    }.not_to change { lead.reload.lead_pipeline_stage_id }
  end
end
