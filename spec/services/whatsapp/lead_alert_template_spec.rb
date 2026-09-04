require "rails_helper"

RSpec.describe Whatsapp::LeadAlertTemplate do
  describe ".for" do
    it "monta o template oficial de aviso de lead sem cabecalho, midia ou botoes" do
      tenant = Tenant.create!(name: "Conexão Imobiliária", slug: "conexao-#{SecureRandom.hex(3)}")
      integration = WhatsappBusinessIntegration.current(tenant)
      integration.update!(waba_id: "waba-lead-alert")

      template = described_class.for(tenant: tenant, integration: integration)

      expect(template.name).to eq("lead_alert")
      expect(template.language).to eq("pt_BR")
      expect(template.category).to eq("UTILITY")
      expect(template.header_format).to eq("none")
      expect(template.footer_text).to be_nil
      expect(template.clean_buttons).to be_empty
      expect(template.body).to eq(described_class::DEFAULT_BODY)
      expect(template.variable_count).to eq(6)
    end

    it "monta os templates oficiais separados para rodizio e bolsao" do
      tenant = Tenant.create!(name: "Templates Imobiliária", slug: "templates-#{SecureRandom.hex(3)}")
      integration = WhatsappBusinessIntegration.current(tenant)
      integration.update!(waba_id: "waba-lead-alerts")

      distribution = described_class.for(tenant: tenant, integration: integration, name: "lead_distribution_alert")
      pool = described_class.for(tenant: tenant, integration: integration, name: "lead_pool_alert")

      expect(distribution.name).to eq("lead_distribution_alert")
      expect(distribution.body).to include("rodízio", "10 minutos")
      expect(distribution.variable_count).to eq(6)
      expect(pool.name).to eq("lead_pool_alert")
      expect(pool.body).to include("bolsão", "Quem pegar primeiro")
      expect(pool.variable_count).to eq(6)
    end

    it "monta payload Meta com somente corpo e seis exemplos" do
      tenant = Tenant.create!(name: "Payload Imobiliária", slug: "payload-#{SecureRandom.hex(3)}")
      integration = WhatsappBusinessIntegration.current(tenant)
      integration.update!(waba_id: "waba-payload")
      template = described_class.for(tenant: tenant, integration: integration)
      template.status = "PENDING"

      expect(template.meta_create_payload).to include(
        name: "lead_alert",
        language: "pt_BR",
        category: "UTILITY"
      )
      expect(template.meta_create_payload[:components]).to eq([
        {
          type: "BODY",
          text: described_class::DEFAULT_BODY,
          example: { body_text: [described_class::EXAMPLE_VALUES] }
        }
      ])
    end
  end
end
