require "rails_helper"

RSpec.describe "Webhooks::Inbound", type: :request do
  before { host! "localhost" }

  let(:admin_user) { create(:admin_user, :admin, name: "Corretor API") }
  let!(:webhook_token) { create(:inbound_webhook_token, admin_user:) }

  it "cria lead de entrada usando token do usuário" do
    expect {
      post "/webhooks/inbound/leads", params: {
        token: webhook_token.token,
        name: "Maria Lead",
        email: "maria@example.test",
        phone: "47999999999",
        keywords: ["elite", "praia"],
        source_url: "https://landing.example.test/praia"
      }, as: :json
    }.to change(Lead, :count).by(1)

    expect(response).to have_http_status(:created)

    lead = Lead.last
    expect(lead.origin).to eq("webhook")
    expect(lead.lead_type).to eq("webhook")
    expect(lead.name).to eq("Maria Lead")
    expect(lead.source_url).to eq("https://landing.example.test/praia")
    expect(lead.other_information["webhook_tags"]).to contain_exactly("elite", "praia")
    expect(lead.other_information["inbound_webhook_user_id"]).to eq(admin_user.id)
    expect(webhook_token.reload.last_received_at).to be_present
  end

  it "aceita token pelo header Authorization Bearer" do
    expect {
      post "/webhooks/inbound/leads",
        params: {
          name: "Lead Header",
          email: "header@example.test",
          phone: "47999999999"
        },
        headers: { "Authorization" => "Bearer #{webhook_token.token}" },
        as: :json
    }.to change(Lead, :count).by(1)

    expect(response).to have_http_status(:created)
    expect(Lead.last.origin).to eq("webhook")
  end

  it "aceita token pelo header X-Webhook-Token" do
    expect {
      post "/webhooks/inbound/leads",
        params: {
          name: "Lead Header Custom",
          email: "header-custom@example.test",
          phone: "47999999999"
        },
        headers: { "X-Webhook-Token" => webhook_token.token },
        as: :json
    }.to change(Lead, :count).by(1)

    expect(response).to have_http_status(:created)
    expect(Lead.last.origin).to eq("webhook")
  end

  it "recusa token inválido sem criar lead" do
    expect {
      post "/webhooks/inbound/leads", params: {
        token: "invalid",
        name: "Maria Lead",
        phone: "47999999999"
      }, as: :json
    }.not_to change(Lead, :count)

    expect(response).to have_http_status(:unauthorized)
  end

  it "valida payload obrigatório" do
    expect {
      post "/webhooks/inbound/leads", params: {
        token: webhook_token.token,
        name: "Sem Telefone"
      }, as: :json
    }.not_to change(Lead, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["details"].join).to include("não pode ficar em branco")
  end
end
