require "rails_helper"

RSpec.describe "Lead attribution capture", type: :request do
  before do
    host! "localhost"
    allow(WebhookService).to receive(:send_form_data)
    allow(LeadMailer).to receive_message_chain(:with, :new_lead_notification, :deliver_later)
    allow(LeadMailer).to receive_message_chain(:with, :welcome_lead, :deliver_later)
    integration = instance_double(
      WhatsappBusinessIntegration,
      whatsapp_url_for: "https://wa.me/5547999999999",
      site_phone_settings: {},
      messaging_ready?: false,
      redirect_after_capture_for?: false
    )
    allow(WhatsappBusinessIntegration).to receive(:current).and_return(integration)
  end

  it "persiste a primeira entrada e classifica o canal no lead" do
    habitation = create(:habitation, codigo: "ATTR-#{SecureRandom.hex(4)}")

    post leads_path, params: {
      lead: {
        name: "Cliente atribuído",
        phone: "47999990000",
        property_id: habitation.id,
        lead_type: "whatsapp_modal",
        page_url: "https://site.example/imoveis/#{habitation.id}",
        landing_url: "https://site.example/campanha?utm_source=google&utm_medium=cpc",
        referrer_url: "https://www.google.com/",
        utm_source: "google",
        utm_medium: "cpc",
        utm_campaign: "aluguel",
        gclid: "click-123"
      }
    }, as: :json

    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.fetch("analytics_event")).to include(
      "event" => "generate_lead", "business_type" => "venda",
      "property_code" => habitation.codigo, "form_id" => "whatsapp_modal"
    )
    expect(response.parsed_body.dig("analytics_event", "event_id")).to match(/\A[0-9a-f-]{36}\z/)
    expect(response.parsed_body.fetch("analytics_event").keys).to contain_exactly(
      "event", "event_id", "business_type", "property_code", "form_id", "phone_e164"
    )
    lead = Lead.order(:created_at).last
    expect(lead).to have_attributes(
      source_url: "https://site.example/imoveis/#{habitation.id}",
      origin: "Google Ads",
      attribution_channel: "google_ads",
      attribution_source: "google"
    )
    expect(lead.attribution_data).to include(
      "landing_url" => "https://site.example/campanha?utm_source=google&utm_medium=cpc",
      "referrer_url" => "https://www.google.com/",
      "utm_campaign" => "aluguel",
      "gclid" => "click-123"
    )
  end

  it "captura o cookie antes do campo oculto e inclui o UID no webhook" do
    cookies["user_id_mh"] = "UID_Ab%2F+"
    post leads_path, params: { lead: { name: "Cliente UID", phone: "47999997776", utm_content: "hidden" } }, as: :json
    expect(response).to have_http_status(:ok)
    lead = Lead.order(:created_at).last
    expect(lead.attribution_data["tracking_uid"]).to eq("UID_Ab%2F+")
    payload = WebhookService.build_payload("lead_created", lead.attributes)
    expect(payload["utm_content"]).to eq("UID_Ab%2F+")
    expect(payload.dig(:source, :utm, "utm_content")).to eq("UID_Ab%2F+")
  end

  it "não anuncia conversão para contato interno ignorado" do
    allow(Leads::InternalContactMatcher).to receive(:call).and_return(double(id: 123))
    expect {
      post leads_path, params: { lead: { name: "Contato interno", phone: "47999990000" } }, as: :json
    }.not_to change(Lead, :count)
    expect(response.parsed_body).to include("success" => true)
    expect(response.parsed_body).not_to have_key("analytics_event")
  end

  it "não anuncia conversão para cadastro inválido" do
    post leads_path, params: { lead: { name: "", phone: "" } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).not_to have_key("analytics_event")
  end

  it "não expõe o código do imóvel de outra conta no evento" do
    other = Tenant.create!(name: "Outra conta", slug: "tracking-other-#{SecureRandom.hex(4)}")
    habitation = create(:habitation, tenant: other, codigo: "OUTRA-CONTA")
    post leads_path, params: { lead: {
      name: "Cliente público", phone: "47999997777", property_id: habitation.id
    } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("analytics_event", "property_code")).to eq("")
  end
end
