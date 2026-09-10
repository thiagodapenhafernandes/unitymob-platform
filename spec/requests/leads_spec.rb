require "rails_helper"

RSpec.describe "Leads", type: :request do
  let(:lead_mailer) { double("LeadMailer parametrizado") }
  let(:welcome_delivery) { double("Boas-vindas", deliver_later: nil) }

  before do
    host! "localhost"
    allow(WebhookService).to receive(:send_form_data)
    allow(LeadMailer).to receive(:with).and_return(lead_mailer)
    allow(lead_mailer).to receive(:welcome_lead).and_return(welcome_delivery)
    expect(lead_mailer).not_to receive(:new_lead_notification)
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
      sale_rent_requires_lead_form: true,
      sale_redirect_after_capture: true,
      rent_redirect_after_capture: true,
      sale_rent_redirect_after_capture: true
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

    it "ignora imóvel de outro tenant ao montar URL de WhatsApp" do
      other_tenant = Tenant.create!(name: "Outro leads #{SecureRandom.hex(3)}", slug: "outro-leads-#{SecureRandom.hex(3)}")
      habitation = create(:habitation, tenant: other_tenant, status: "Aluguel", valor_venda_cents: 0, valor_locacao_cents: 4_500_00)

      get whatsapp_url_leads_path, params: { property_id: habitation.id, message: "Quero alugar" }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["negotiation_type"]).to eq("sale")
      expect(body["whatsapp_url"]).to include("wa.me/5547999990001")
    end

    it "usa tenant_slug para resolver imóvel do tenant público solicitado" do
      tenant = Tenant.create!(name: "Tenant publico leads #{SecureRandom.hex(3)}", slug: "tenant-publico-leads-#{SecureRandom.hex(3)}")
      habitation = create(:habitation, tenant: tenant, status: "Aluguel", valor_venda_cents: 0, valor_locacao_cents: 4_500_00)

      get whatsapp_url_leads_path, params: { tenant_slug: tenant.slug, property_id: habitation.id, message: "Quero alugar" }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["negotiation_type"]).to eq("rent")
      expect(body["whatsapp_url"]).to include("wa.me/5547999990002")
    end
  end

  describe "POST /leads" do
    it "persiste a primeira origem separada da conversão e encaminha os identificadores" do
      post leads_path, params: { lead: {
        name: "Atribuição multicanal", phone: "47999992345", origin: "Site", lead_type: "whatsapp_modal",
        page_url: "http://localhost/imovel", first_touch: { gbraid: "GoogleFirst" },
        conversion_touch: { ttclid: "TikTokLast", utm_source: "tiktok", utm_campaign: "Lançamento", landing_url: "http://localhost/imovel" }
      } }, as: :json
      expect(response).to have_http_status(:ok)
      lead = Lead.order(:created_at).last
      expect(lead.attribution_channel).to eq("tiktok_ads")
      expect(lead.origin).to eq("Site")
      expect(lead.attribution_data.dig("first_touch", "channel")).to eq("google_ads")
      expect(lead.attribution_data.dig("conversion_touch", "ttclid")).to eq("TikTokLast")
      expect(WebhookService).to have_received(:send_form_data).with(
        "whatsapp_lead", hash_including(ttclid: "TikTokLast"), anything
      )
    end

    it "mantém as boas-vindas ao cliente sem avisar o e-mail principal da imobiliária" do
      post leads_path, params: {
        lead: { name: "Cliente Site", phone: "47999991234", email: "cliente@example.com" }
      }, as: :json

      expect(response).to have_http_status(:ok)
      lead = Lead.order(:created_at).last
      expect(LeadMailer).to have_received(:with).with(lead: lead)
      expect(welcome_delivery).to have_received(:deliver_later).once
    end

    it "não agenda e-mails do formulário quando o cliente não informa e-mail" do
      post leads_path, params: {
        lead: { name: "Cliente Sem Email", phone: "47999991235" }
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(LeadMailer).not_to have_received(:with)
    end

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

    it "reaproveita lead whatsapp_modal recente em duplo envio do formulário" do
      habitation = create(:habitation, valor_venda_cents: 700_000_00, valor_locacao_cents: 0)
      payload = {
        lead: {
          name: "Cliente Duplicado",
          phone: "(47) 98888-0000",
          email: "",
          property_id: habitation.id,
          lead_type: "whatsapp_modal",
          whatsapp_message: "Tenho interesse",
          business_type: "sale",
          page_url: "https://site.example/imoveis/#{habitation.id}"
        }
      }

      expect {
        2.times { post leads_path, params: payload, as: :json }
      }.to change(Lead, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(WebhookService).to have_received(:send_form_data).once
      expect(Lead.order(:created_at).last.phone).to eq("5547988880000")
    end

    it "creates the lead and returns a confirmation message when WhatsApp redirect is disabled" do
      WhatsappBusinessIntegration.current(Tenant.default).update!(sale_redirect_after_capture: false)
      habitation = create(:habitation, valor_venda_cents: 700_000_00, valor_locacao_cents: 0)

      expect {
        post leads_path, params: {
          lead: {
            name: "Cliente Sem Redirecionamento",
            phone: "(47) 99999-9998",
            property_id: habitation.id,
            lead_type: "whatsapp_modal",
            whatsapp_message: "Tenho interesse",
            business_type: "sale"
          }
        }, as: :json
      }.to change(Lead, :count).by(1)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["success"]).to be(true)
      expect(body["message"]).to include("Um corretor da nossa equipe")
      expect(body).not_to have_key("whatsapp_url")
    end

    it "classifica como Site quando o lead veio do proprio site sem origem explicita" do
      host! "site.example"
      habitation = create(:habitation, valor_venda_cents: 700_000_00, valor_locacao_cents: 0)

      post leads_path, params: {
        lead: {
          name: "Cliente Site",
          phone: "(47) 99999-1111",
          property_id: habitation.id,
          lead_type: "whatsapp_modal",
          whatsapp_message: "Tenho interesse",
          business_type: "sale",
          page_url: "https://site.example/imoveis/#{habitation.id}"
        }
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(Lead.order(:created_at).last.origin).to eq("Site")
    end

    it "preserva origem explicita mesmo quando o lead veio do proprio site" do
      host! "site.example"
      habitation = create(:habitation, valor_venda_cents: 700_000_00, valor_locacao_cents: 0)

      post leads_path, params: {
        lead: {
          name: "Cliente Compartilhamento",
          phone: "(47) 99999-2222",
          property_id: habitation.id,
          lead_type: "whatsapp_modal",
          origin: "Compartilhamento Corretor",
          whatsapp_message: "Tenho interesse",
          business_type: "sale",
          page_url: "https://site.example/imoveis/#{habitation.id}"
        }
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(Lead.order(:created_at).last.origin).to eq("Compartilhamento Corretor")
    end

    it "cria lead no tenant público e descarta property_id de outro tenant" do
      other_tenant = Tenant.create!(name: "Outro leads #{SecureRandom.hex(3)}", slug: "outro-leads-#{SecureRandom.hex(3)}")
      habitation = create(:habitation, tenant: other_tenant, valor_venda_cents: 700_000_00, valor_locacao_cents: 0)

      expect {
        post leads_path, params: {
          lead: {
            name: "Cliente Cross Tenant",
            phone: "(47) 98888-7777",
            property_id: habitation.id,
            lead_type: "whatsapp_modal"
          }
        }, as: :json
      }.to change(Lead, :count).by(1)

      expect(response).to have_http_status(:ok)
      lead = Lead.order(:created_at).last
      expect(lead.tenant).to eq(Tenant.default)
      expect(lead.property_id).to be_nil
    end

    it "cria lead no tenant público informado por tenant_slug" do
      tenant = Tenant.create!(name: "Tenant lead publico #{SecureRandom.hex(3)}", slug: "tenant-lead-publico-#{SecureRandom.hex(3)}")
      habitation = create(:habitation, tenant: tenant, valor_venda_cents: 700_000_00, valor_locacao_cents: 0)

      post leads_path, params: {
        tenant_slug: tenant.slug,
        lead: {
          name: "Cliente Tenant",
          phone: "47999990000",
          property_id: habitation.id,
          origin: "site"
        }
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(tenant.leads.order(:created_at).last).to have_attributes(name: "Cliente Tenant", property_id: habitation.id)
    end
  end
end
