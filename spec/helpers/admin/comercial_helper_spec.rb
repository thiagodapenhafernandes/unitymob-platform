require "rails_helper"

RSpec.describe Admin::ComercialHelper, type: :helper do
  describe "#lead_conversion_summary" do
    it "prefere a origem original do C2S em leads migrados" do
      lead = build_stubbed(
        :lead,
        origin: ExternalLeadIntegration::LEAD_ORIGIN,
        lead_type: "webhook",
        attribution_source: "Portal parceiro",
        attribution_channel: "Landing Page",
        attribution_data: {
          "provider" => ExternalLeadMigration::LeadMapper::PROVIDER_KEY,
          "lead_source" => { "name" => "Portal parceiro" },
          "channel" => { "name" => "Landing Page" }
        },
        other_information: {
          "source" => ExternalLeadMigration::LeadMapper::PROVIDER_KEY
        }
      )

      summary = helper.lead_conversion_summary(lead)

      expect(summary[:origin]).to eq("Portal parceiro")
      expect(summary[:channel_label]).to eq("Landing Page")
      expect(summary[:channel_label]).not_to eq("Webhook")
    end

    it "mantem a origem do lead quando nao veio da migracao externa" do
      lead = build_stubbed(:lead, origin: "Facebook Leads", lead_type: nil)

      expect(helper.lead_conversion_summary(lead)[:origin]).to eq("Facebook Leads")
    end

    it "usa fonte e canal comerciais em leads recebidos por webhook nativo" do
      lead = build_stubbed(
        :lead,
        origin: "webhook",
        lead_type: "webhook",
        product: "Apartamento no Centro",
        other_information: {
          "source" => "Instagram Leads",
          "channel" => "social",
          "webhook_payload" => {
            "utm_source" => "instagram",
            "utm_medium" => "social"
          }
        }
      )

      summary = helper.lead_conversion_summary(lead)

      expect(summary[:origin]).to eq("Instagram Leads")
      expect(summary[:channel_label]).to eq("Rede Social")
      expect(helper.lead_card_interest_line(lead, summary)).to eq("Rede Social - Apartamento no Centro")
    end

    it "separa origem direta da conversao feita pelo site" do
      lead = build_stubbed(
        :lead,
        origin: "Site",
        lead_type: "whatsapp_modal",
        source_url: "https://conexaobc.com/imoveis/apartamento-centro-2431",
        attribution_channel: "direct",
        attribution_data: {
          "captured_at" => "2026-09-03T15:54:25-03:00",
          "landing_url" => "https://conexaobc.com/imoveis/apartamento-centro-2431"
        }
      )

      summary = helper.lead_conversion_summary(lead)

      expect(summary[:channel]).to eq(:direct)
      expect(summary[:lead_origin_label]).to eq("Direto / origem desconhecida")
      expect(summary[:conversion_origin_label]).to eq("Site")
      expect(summary[:headline]).to eq("Criado por um formulário do site")
      expect(helper.lead_conversion_summary_label(summary)).to eq("Origem: Direto / origem desconhecida · Conversão: Site")
    end

    it "mantem origem de midia separada da conversao pelo site" do
      lead = build_stubbed(
        :lead,
        origin: "Site",
        lead_type: "whatsapp_modal",
        source_url: "https://conexaobc.com/imoveis/apartamento-centro-2431",
        attribution_source: "google",
        attribution_channel: "google_ads",
        attribution_data: {
          "utm_source" => "google",
          "utm_medium" => "cpc",
          "landing_url" => "https://conexaobc.com/imoveis/apartamento-centro-2431"
        }
      )

      summary = helper.lead_conversion_summary(lead)

      expect(summary[:lead_origin_label]).to eq("Google Ads")
      expect(summary[:conversion_origin_label]).to eq("Site")
      expect(helper.lead_conversion_origin_badge_label(summary)).to eq("Conversão: Site")
      expect(helper.lead_tracking_origin_text(summary)).to eq("Origem: Google Ads")
    end

    it "aproveita utm_source quando o canal veio como direto" do
      lead = build_stubbed(
        :lead,
        origin: "Site",
        lead_type: "whatsapp_modal",
        source_url: "https://conexaobc.com/imoveis/apartamento-centro-2431",
        attribution_channel: "direct",
        attribution_data: {
          "utm_source" => "google",
          "landing_url" => "https://conexaobc.com/imoveis/apartamento-centro-2431"
        }
      )

      summary = helper.lead_conversion_summary(lead)

      expect(summary[:channel_label]).to eq("Direto / origem desconhecida")
      expect(summary[:lead_origin_label]).to eq("Google")
      expect(summary[:conversion_origin_label]).to eq("Site")
    end
  end

  describe "#lead_card_interest_line" do
    it "troca webhook tecnico por canal comercial em leads C2S" do
      lead = build_stubbed(
        :lead,
        origin: ExternalLeadIntegration::LEAD_ORIGIN,
        lead_type: "webhook",
        product: "[3937] Form Varekai",
        attribution_data: {
          "provider" => ExternalLeadMigration::LeadMapper::PROVIDER_KEY,
          "channel" => { "name" => "Landing Page" }
        },
        other_information: {
          "source" => ExternalLeadMigration::LeadMapper::PROVIDER_KEY
        }
      )

      expect(helper.lead_card_interest_line(lead)).to eq("Landing Page - [3937] Form Varekai")
    end

    it "usa origem e canal do payload legado C2S" do
      lead = build_stubbed(
        :lead,
        origin: "C2S",
        lead_type: "webhook",
        other_information: {
          "source" => "c2s",
          "attributes" => {
            "lead_source" => { "name" => "Instagram Leads" },
            "channel" => { "name" => "Internet" }
          }
        }
      )

      summary = helper.lead_conversion_summary(lead)

      expect(summary[:origin]).to eq("Instagram Leads")
      expect(summary[:channel_label]).to eq("Internet")
    end
  end

  describe "#lead_card_business_label" do
    it "identifica venda pelo produto importado do C2S" do
      lead = build_stubbed(
        :lead,
        product: "[7991] | Venda | Residencial Ecoville",
        other_information: { "source" => ExternalLeadMigration::LeadMapper::PROVIDER_KEY }
      )

      expect(helper.lead_card_business_label(lead)).to eq("Venda")
    end

    it "identifica locacao pela negociacao do payload C2S" do
      lead = build_stubbed(
        :lead,
        product: "Apartamento no Centro",
        attribution_data: {
          "product" => {
            "real_estate_detail" => {
              "negotiation_name" => "Locação anual"
            }
          }
        },
        other_information: { "source" => ExternalLeadMigration::LeadMapper::PROVIDER_KEY }
      )

      expect(helper.lead_card_business_label(lead)).to eq("Locação")
    end

    it "identifica captacao quando o lead veio para captar imovel" do
      lead = build_stubbed(:lead, product: "Captar apto", lead_type: "webhook")

      expect(helper.lead_card_business_label(lead)).to eq("Captação")
    end
  end

  describe "#lead_card_note_line" do
    it "traduz rotulos tecnicos em ingles para texto comum" do
      lead = build_stubbed(
        :lead,
        notes: "Full name: Sara franca Phone number: 5541996607000 Message: Quero atendimento",
        origin: ExternalLeadIntegration::LEAD_ORIGIN,
        attribution_data: { "provider" => ExternalLeadMigration::LeadMapper::PROVIDER_KEY },
        other_information: { "source" => ExternalLeadMigration::LeadMapper::PROVIDER_KEY }
      )

      expect(helper.lead_card_note_line(lead)).to eq(
        "Nome completo: Sara franca Telefone: 5541996607000 Mensagem: Quero atendimento"
      )
    end

    it "nao exibe payload tecnico serializado no card do lead" do
      lead = build_stubbed(
        :lead,
        notes: '{"id"=>"4e42462f78f54164142a48ca83e2b75f", "sender_id"=>"7c123"}',
        origin: "Facebook",
        lead_type: "WhatsApp"
      )

      expect(helper.lead_card_note_line(lead)).to eq("Facebook")
    end
  end
end
