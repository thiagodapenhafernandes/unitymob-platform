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
      messaging_ready?: false
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
end
