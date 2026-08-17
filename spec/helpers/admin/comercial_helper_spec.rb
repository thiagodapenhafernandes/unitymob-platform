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
  end
end
