require "rails_helper"

RSpec.describe "Leads", type: :request do
  before do
    host! "localhost"
    allow(WebhookService).to receive(:send_form_data)
    allow(LeadMailer).to receive_message_chain(:with, :new_lead_notification, :deliver_later)
    allow(LeadMailer).to receive_message_chain(:with, :welcome_lead, :deliver_later)
    WhatsappBusinessIntegration.delete_all
    Whatsapp::SiteRouting.update!(
      default_number: "47 3311-1067",
      rules: {
        "sale" => { "number" => "47 99999-0001", "capture_enabled" => "1" },
        "rent" => { "number" => "47 99999-0002", "capture_enabled" => "0" },
        "sale_rent" => { "number" => "47 99999-0003", "capture_enabled" => "1" }
      }
    )
    create(
      :whatsapp_business_integration,
      default_whatsapp_number: "47 3311-1067",
      sale_whatsapp_number: "47 99999-0001",
      rent_whatsapp_number: "47 99999-0002",
      sale_rent_whatsapp_number: "47 99999-0003",
      sale_requires_lead_form: true,
      rent_requires_lead_form: false,
      sale_rent_requires_lead_form: true
    )
  end

  describe "GET /leads/whatsapp_url" do
    it "returns routing metadata for the property negotiation type" do
      habitation = create(:habitation, status: "Aluguel", valor_venda_cents: 0, valor_locacao_cents: 4_500_00)

      get whatsapp_url_leads_path, params: { property_id: habitation.id, message: "Quero alugar" }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to include(
        "capture_required" => false,
        "negotiation_type" => "rent",
        "negotiation_label" => "Locação"
      )
      expect(body["whatsapp_url"]).to include("wa.me/5547999990002")
    end
  end

  describe "POST /leads" do
    it "creates the lead and returns the configured WhatsApp URL" do
      habitation = create(:habitation, valor_venda_cents: 700_000_00, valor_locacao_cents: 0)

      expect(WebhookService).to receive(:send_form_data).with(
        "whatsapp_lead",
        hash_including(
          business_type: "sale",
          business_type_label: "Venda",
          property_code: habitation.codigo,
          property_title: habitation.display_title,
          page_url: "https://site.example/imoveis/#{habitation.id}",
          utm_source: "google"
        ),
        request: kind_of(ActionDispatch::Request)
      )

      expect {
        post leads_path, params: {
          lead: {
            name: "Cliente Teste",
            phone: "(47) 99999-9999",
            email: "",
            property_id: habitation.id,
            lead_type: "whatsapp_modal",
            whatsapp_message: "Tenho interesse",
            business_type: "sale",
            page_url: "https://site.example/imoveis/#{habitation.id}",
            utm_source: "google"
          }
        }, as: :json
      }.to change(Lead, :count).by(1)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["success"]).to be(true)
      expect(body["whatsapp_url"]).to include("wa.me/5547999990001")
    end
  end
end
