require "rails_helper"

RSpec.describe "Proteção da carteira espelhada C2S" do
  let(:tenant) { Tenant.default }
  let(:owner) { create(:admin_user, tenant: tenant) }
  let(:integration) { create(:external_lead_integration, tenant: tenant, connected_by_admin_user: owner, mirror_c2s_owners: true) }
  let(:lead) { create(:lead, tenant: tenant, external_lead_integration: integration, admin_user: owner, status: "Descartado") }

  it "mantém o responsável numa reentrada sem regra ativa" do
    tenant.distribution_rules.update_all(active: false)
    inquiry = build(:lead, tenant: tenant)

    expect { Leads::DistributorService.redistribute(lead, inquiry: inquiry) }
      .not_to change { lead.reload.attributes.slice("admin_user_id", "status", "distribution_rule_id") }
    expect(lead.activities.where(kind: "distribution_failed")).to be_empty
  end

  it "não executa distribuição automática, regra explícita ou indicação de corretor" do
    rule = create(:distribution_rule, tenant: tenant, active: true)
    other = create(:admin_user, tenant: tenant)

    expect {
      Leads::DistributorService.find_and_distribute(lead)
      Leads::DistributorService.distribute_to(lead, rule)
      Leads::DistributorService.distribute_to_agent(lead, rule, other)
      Automation::ActionExecutor.execute({ type: "assign_agent", admin_user_id: other.id }, lead)
    }.not_to change { lead.reload.admin_user_id }
  end

  it "preserva o fluxo de reentrada quando o espelhamento é desligado" do
    lead
    integration.update!(mirror_c2s_owners: false)
    tenant.distribution_rules.update_all(active: false)

    expect { Leads::DistributorService.redistribute(lead.reload, inquiry: build(:lead, tenant: tenant)) }
      .to change { lead.reload.admin_user_id }.from(owner.id).to(nil)
  end

  it "pula a automação do espelho sem consumir o limite dos outros leads" do
    pipeline = create(:lead_pipeline, tenant: tenant)
    source = create(:lead_pipeline_stage, tenant: tenant, lead_pipeline: pipeline)
    target = create(:lead_pipeline_stage, tenant: tenant, lead_pipeline: pipeline)
    create(:lead_pipeline_stage_automation, tenant: tenant, lead_pipeline_stage: source, auto_advance_to_stage: target)
    mirrored = create(:lead, tenant: tenant, admin_user: owner, external_lead_integration: integration,
      lead_pipeline: pipeline, lead_pipeline_stage: source, status: source.name, created_at: 3.days.ago)
    local = create(:lead, tenant: tenant, lead_pipeline: pipeline, lead_pipeline_stage: source,
      status: source.name, created_at: 3.days.ago)

    Leads::PipelineStageAutoAdvanceService.call(tenant: tenant, limit: 1)

    expect(mirrored.reload.lead_pipeline_stage_id).to eq(source.id)
    expect(local.reload.lead_pipeline_stage_id).to eq(target.id)
  end
end
