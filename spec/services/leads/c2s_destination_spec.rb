require "rails_helper"

RSpec.describe "Destino C2S da distribuição" do
  let(:tenant) { Tenant.default }
  let!(:integration) { create(:external_lead_integration, tenant: tenant, export_enabled: false) }
  let!(:rule) { create(:distribution_rule, tenant: tenant, delivery_destination: "c2s", source_whatsapp_campaign: true) }

  it "encaminha sem corretores, aceite, check-in ou notificação local" do
    rule.update!(require_active_checkin: true, distribution_mode: :shark_tank, pocket_active: true, pocket_time: 5)
    expect(Leads::NotificationDispatcher).not_to receive(:deliver)
    expect(Leads::NotificationDispatcher).not_to receive(:notify_shark_tank)
    lead = nil
    expect { lead = Leads::Intake.create!(tenant: tenant, name: "Maria", phone: "11987654321", origin: "Site") }
      .to have_enqueued_job(ExternalLeadMigration::ExportLeadJob).once
    expect(lead.reload).to have_attributes(distribution_rule_id: rule.id, admin_user_id: nil, distribution_cycle_started_at: nil)
    expect(lead.activities.where(kind: "external_lead_export_queued")).to exist
    expect(lead.activities.where(kind: %w[distributed shark_tank_ready])).not_to exist
    expect(rule.pool_mode?).to be(false)
    expect(rule.pocket_operational?).to be(false)
  end

  it "também funciona como fila explicitamente selecionada na campanha" do
    admin = create(:admin_user, :admin, tenant: tenant)
    template = WhatsappTemplate.create!(name: "campaign_c2s", status: "APPROVED", body: "Olá")
    campaign = WhatsappCampaign.create!(name: "Campanha C2S", whatsapp_template: template, created_by: admin)
    recipient = campaign.campaign_recipients.create!(name: "Maria", phone_number: "11987654321")
    expect { recipient.convert_to_lead!(distribution_rule: rule) }.to have_enqueued_job(ExternalLeadMigration::ExportLeadJob)
    expect(recipient.reload.lead).to have_attributes(distribution_rule_id: rule.id, admin_user_id: nil)
  end

  it "preserva as regras locais existentes e permite voltar ao destino Unitymob" do
    agent = create(:admin_user, :field_agent, tenant: tenant)
    create(:distribution_rule_agent, distribution_rule: rule, admin_user: agent)
    rule.update!(delivery_destination: "unitymob")
    lead = Leads::Intake.create!(tenant: tenant, name: "João", phone: "11987654322", origin: "Site")
    expect(lead.reload.admin_user_id).to eq(agent.id)
    expect(rule.reload.distribution_rule_agents.count).to eq(1)
  end

  it "não usa contingência local ao esperar envio ao C2S" do
    fallback = create(:distribution_rule, tenant: tenant, source_site: false)
    rule.update!(contingency_enabled: true, contingency_rule: fallback, contingency_triggers: ["unavailable"])
    lead = Leads::Intake.create!(tenant: tenant, name: "Maria", phone: "11987654321", origin: "Site")
    expect(Leads::ContingencyService.check!(lead)).to be_nil
    expect(lead.reload.distribution_rule_id).to eq(rule.id)
  end

  it "não devolve ao C2S um lead que veio dele" do
    owner = create(:admin_user, :field_agent, tenant: tenant)
    lead = create(:lead, tenant: tenant, admin_user: owner, external_lead_integration: integration, external_lead_id: "remote-1", skip_automatic_routing: true)
    expect { Leads::DistributorService.distribute_to(lead, rule) }.not_to have_enqueued_job(ExternalLeadMigration::ExportLeadJob)
    expect(lead.activities.where(kind: "external_lead_export_skipped")).to exist
    expect(lead.reload.admin_user_id).to eq(owner.id)
  end

  it "exige conexão da própria conta e permite desligar uma regra desconectada" do
    integration.update!(status: "disconnected")
    expect(rule.reload).not_to be_valid
    rule.active = false
    expect(rule).to be_valid
    expect(build(:distribution_rule, delivery_destination: "unitymob")).to be_valid
  end
end
