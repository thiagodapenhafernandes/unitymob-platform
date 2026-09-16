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
end
