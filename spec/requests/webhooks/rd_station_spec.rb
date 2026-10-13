require "rails_helper"

RSpec.describe "Webhooks::RdStation", type: :request do
  before { host! "localhost" }

  let(:tenant) { Tenant.default }
  let(:agent) { create(:admin_user, :field_agent, tenant:) }
  let!(:rule) { create(:distribution_rule, tenant:, source_site: false, source_rd_station: true) }

  before do
    create(:distribution_rule_agent, distribution_rule: rule, admin_user: agent)
    Setting.set(RdStationIntegrationSetting::WEBHOOK_SECRET_KEY, "rd-webhook-secret", tenant:)
  end

  it "recebe lead da RD Station e distribui pela fonte RD" do
    expect {
      post "/webhooks/rd_station/rd-webhook-secret", params: {
        event_type: "WEBHOOK.CONVERTED",
        contact: {
          uuid: "contact-123",
          name: "Cliente RD",
          email: "cliente-rd@example.test",
          mobile_phone: "47 99999-2222",
          tags: ["campanha-x"],
          conversion_identifier: "Landing Praia",
          utm_campaign: "Campanha Praia",
          utm_source: "newsletter",
          utm_medium: "email"
        }
      }, as: :json
    }.to change(Lead, :count).by(1)

    expect(response).to have_http_status(:created)
    lead = Lead.last
    expect(lead.origin).to eq("RD Station")
    expect(lead.lead_type).to eq("rd_station")
    expect(lead.distribution_rule_id).to eq(rule.id)
    expect(lead.admin_user_id).to eq(agent.id)
    expect(lead.other_information["rd_station_contact_uuid"]).to eq("contact-123")
    expect(lead.other_information["rd_station_conversion_identifier"]).to eq("Landing Praia")
    expect(lead.other_information["rd_station_campaign_name"]).to eq("Campanha Praia")
    expect(lead.other_information["rd_station_source"]).to eq("newsletter")
    expect(lead.other_information["rd_station_medium"]).to eq("email")
  end

  it "recusa token inválido" do
    expect {
      post "/webhooks/rd_station/invalido", params: { contact: { name: "Cliente RD" } }, as: :json
    }.not_to change(Lead, :count)

    expect(response).to have_http_status(:unauthorized)
  end

  it "ignora Meta bloqueada antes de complementar ou redistribuir um lead existente" do
    lead = create(:lead, tenant:, phone: "47999992222", status: "Represado", origin: "Facebook Lead Ads")
    original = lead.attributes
    Setting.set(RdStationIntegrationSetting::BLOCKED_SOURCES_KEY, '["meta"]', tenant:)
    expect(Leads::Intake).not_to receive(:receive!)
    expect {
      post "/webhooks/rd_station/rd-webhook-secret", params: {
        contact: { name: "Cliente RD", mobile_phone: "47999992222", tags: ["instagram leads"], funnel: { origin: "Desconhecido" } }
      }, as: :json
    }.not_to change(LeadActivity, :count)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("ignored" => true, "reason" => "blocked_source", "source" => "meta")
    expect(lead.reload.attributes).to eq(original)
  end

  it "bloqueia outras fontes configuradas e permite fontes não bloqueadas" do
    Setting.set(RdStationIntegrationSetting::BLOCKED_SOURCES_KEY, '["google","parceiro aurea","unknown"]', tenant:)
    [{ funnel: { origin: "Busca Paga | Google" } }, { utm_source: "Parceiro Áurea" }, {}].each do |source|
      post "/webhooks/rd_station/rd-webhook-secret", params: { contact: { name: "Contato" }.merge(source) }, as: :json
      expect(response.parsed_body["ignored"]).to eq(true)
    end
    expect {
      post "/webhooks/rd_station/rd-webhook-secret", params: { contact: { name: "Permitido", mobile_phone: "47999995555", utm_source: "linkedin" } }, as: :json
    }.to change(tenant.leads, :count).by(1)
    expect(response).to have_http_status(:created)
  end

  it "não aplica o bloqueio de outra conta" do
    other = Tenant.create!(name: "Outra RD", slug: "outra-rd-#{SecureRandom.hex(4)}")
    Setting.set(RdStationIntegrationSetting::BLOCKED_SOURCES_KEY, '["meta"]', tenant: other)
    expect {
      post "/webhooks/rd_station/rd-webhook-secret", params: { contact: { name: "Permitido", mobile_phone: "47999995555", utm_source: "facebook" } }, as: :json
    }.to change(tenant.leads, :count).by(1)
  end
end
