require "rails_helper"

RSpec.describe WhatsappCampaignRecipient, type: :model do
  let(:admin) { create(:admin_user, :admin) }
  let(:template) { WhatsappTemplate.create!(name: "campaign_queue", status: "APPROVED", body: "Olá") }
  let(:campaign) { WhatsappCampaign.create!(name: "Fila da campanha", whatsapp_template: template, created_by: admin) }
  let(:recipient) { campaign.campaign_recipients.create!(name: "Maria", phone_number: "11988887777") }
  let(:rule) { create(:distribution_rule, source_site: false, source_whatsapp_campaign: true) }
  let(:agent) { create(:admin_user, :field_agent) }

  before do
    create(:distribution_rule_agent, distribution_rule: rule, admin_user: agent)
  end

  it "entrega apenas à fila selecionada, com aceite, sem depender das fontes ou filtros de outras filas" do
    create(:distribution_rule, source_site: true, source_whatsapp_campaign: true)
    rule.update!(property_cities: ["Curitiba"], business_type: :venda)

    lead = recipient.convert_to_lead!(distribution_rule: rule)

    expect(lead.reload).to have_attributes(distribution_rule_id: rule.id, admin_user_id: agent.id, status: "Aguardando Aceite")
    expect(lead.activities.where(kind: "distributed").count).to eq(1)
    expect { recipient.convert_to_lead!(distribution_rule: rule) }.not_to change(Lead, :count)
  end

  it "usa a fila e a origem da campanha mesmo quando a planilha indica origem e responsável" do
    recipient.update!(origin: "importacao", admin_user: admin)
    lead = recipient.convert_to_lead!(distribution_rule: rule)
    expect(lead.reload).to have_attributes(origin: "whatsapp_campaign", distribution_rule_id: rule.id, admin_user_id: agent.id)
  end

  it "mantém na fila escolhida quando exige check-in e não há corretor disponível" do
    rule.update!(require_active_checkin: true)
    lead = recipient.convert_to_lead!(distribution_rule: rule)
    expect(lead.reload).to have_attributes(distribution_rule_id: rule.id, admin_user_id: nil, status: "Represado")
  end

  it "não redistribui por outra fonte quando o recebimento de campanhas foi desligado" do
    rule.update!(source_whatsapp_campaign: false)
    lead = recipient.convert_to_lead!(distribution_rule: rule)
    expect(lead.reload).to have_attributes(distribution_rule_id: rule.id, admin_user_id: nil, status: "Represado")
    expect(lead.activities.where(kind: "distribution_failed").last.metadata["reason"]).to eq("campaign_source_disabled")
  end

  it "aplica a contingência configurada mesmo quando o destino não recebe campanhas diretamente" do
    destination = create(:distribution_rule, source_site: false)
    create(:distribution_rule_agent, distribution_rule: destination, admin_user: agent)
    rule.distribution_rule_agents.destroy_all
    rule.update!(contingency_enabled: true, contingency_rule: destination, contingency_triggers: ["unavailable"], contingency_unavailable_minutes: 0)
    lead = recipient.convert_to_lead!(distribution_rule: rule)
    expect(lead.reload).to have_attributes(distribution_rule_id: destination.id, admin_user_id: agent.id)
  end

  it "reutiliza o cadastro existente e aplica a fila selecionada na reentrada" do
    existing = create(:lead, phone: recipient.phone_number, skip_automatic_routing: true)
    expect { recipient.convert_to_lead!(distribution_rule: rule) }.not_to change(Lead, :count)
    expect(recipient.reload.lead_id).to eq(existing.id)
    expect(existing.reload).to have_attributes(distribution_rule_id: rule.id, admin_user_id: agent.id)
  end

  it "rejeita uma fila de outra conta" do
    foreign_tenant = Tenant.create!(name: "Outra", slug: "campaign-queue-#{SecureRandom.hex(4)}")
    foreign_rule = create(:distribution_rule, tenant: foreign_tenant, source_whatsapp_campaign: true)
    expect { recipient.convert_to_lead!(distribution_rule: foreign_rule) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "não roda a fila duas vezes ao converter pela automação da campanha" do
    event = AutomationEvent.create!(tenant: campaign.tenant, name: "whatsapp_campaign_message_replied", source: "whatsapp", payload: { whatsapp_campaign_recipient_id: recipient.id })
    executor = Automation::ActionExecutor.new(nil, automation_event: event)
    executor.execute(type: "set_flow_result", result: "generates_attendance", distribution_rule_id: rule.id)
    lead = recipient.reload.lead
    expect(lead).to be_present
    expect(lead.activities.where(kind: "distributed").count).to eq(1)
  end
end
