require "rails_helper"

RSpec.describe Leads::PipelineStageAutoAdvanceService do
  let(:tenant) { Tenant.default }
  let(:pipeline) { create(:lead_pipeline, tenant: tenant) }
  let(:source_stage) do
    create(:lead_pipeline_stage, tenant: tenant, lead_pipeline: pipeline, name: "Sem retorno")
  end
  let(:destination_stage) { create(:lead_pipeline_stage, tenant: tenant, lead_pipeline: pipeline, name: "Nutrição") }

  it "move leads vencidos que continuam na etapa configurada" do
    automation = create(:lead_pipeline_stage_automation, lead_pipeline_stage: source_stage, tenant: tenant, auto_advance_to_stage: destination_stage)
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
      described_class.call
    }.to change { lead.reload.lead_pipeline_stage_id }.from(source_stage.id).to(destination_stage.id)

    expect(lead.status).to eq(destination_stage.name)
    metadata = lead.activities.where(kind: "status_change").last.metadata
    expect(metadata["by"]).to eq("Automação da etapa")
    expect(metadata["stage_automation_id"]).to eq(automation.id)
  end

  it "permite mover para etapa de outro funil do mesmo tenant" do
    other_pipeline = create(:lead_pipeline, tenant: tenant, name: "Pós-venda")
    destination = create(:lead_pipeline_stage, tenant: tenant, lead_pipeline: other_pipeline, name: "Reativar")
    create(:lead_pipeline_stage_automation, lead_pipeline_stage: source_stage, tenant: tenant, auto_advance_to_stage: destination)
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
      described_class.call
    }.to change { lead.reload.lead_pipeline_id }.from(pipeline.id).to(other_pipeline.id)

    expect(lead.lead_pipeline_stage_id).to eq(destination.id)
  end

  it "mantem o lead na etapa quando houve interacao do cliente dentro do prazo" do
    create(
      :lead_pipeline_stage_automation,
      lead_pipeline_stage: source_stage,
      tenant: tenant,
      auto_advance_to_stage: destination_stage,
      trigger: "customer_inactivity"
    )
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
    LeadActivity.create!(tenant: tenant, lead: lead, kind: "whatsapp_in", created_at: 1.day.ago, updated_at: 1.day.ago)

    expect {
      described_class.call
    }.not_to change { lead.reload.lead_pipeline_stage_id }
  end
end
