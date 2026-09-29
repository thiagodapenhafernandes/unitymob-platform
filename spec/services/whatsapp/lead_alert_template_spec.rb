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

    it "monta as variantes v2 com botão Salvar contato e mesmo corpo" do
      tenant = Tenant.create!(name: "V2 Imobiliária", slug: "v2-#{SecureRandom.hex(3)}")
      integration = WhatsappBusinessIntegration.current(tenant)
      integration.update!(waba_id: "waba-v2")

      rotary = described_class.for(tenant: tenant, integration: integration, name: "lead_distribution_alert_v2")
      pool = described_class.for(tenant: tenant, integration: integration, name: "lead_pool_alert_utility_v2")

      expect(rotary.body).to eq(described_class::DISTRIBUTION_BODY)
      expect(rotary.clean_buttons).to eq([{ "kind" => "quick_reply", "text" => "Salvar contato" }])
      expect(rotary.variable_count).to eq(6)
      expect(pool.body).to include("aguardando aceite no bolsão")
      expect(pool.clean_buttons).to eq([{ "kind" => "quick_reply", "text" => "Salvar contato" }])
      expect(pool.variable_count).to eq(6)
      expect(described_class.names).to include("lead_distribution_alert_v2", "lead_pool_alert_utility_v2")
    end

    it "preserva botoes do registro existente ao montar v2" do
      tenant = Tenant.create!(name: "V2 Keep Imobiliária", slug: "v2keep-#{SecureRandom.hex(3)}")
      integration = WhatsappBusinessIntegration.current(tenant)
      integration.update!(waba_id: "waba-v2keep")
      tenant.whatsapp_templates.create!(
        name: "lead_distribution_alert_v2", language: "pt_BR", waba_id: integration.waba_id,
        category: "UTILITY", status: "APPROVED", template_type: "text", header_format: "none",
        body: described_class::DISTRIBUTION_BODY,
        buttons: [{ "kind" => "quick_reply", "text" => "Salvar contato" }]
      )

      template = described_class.for(tenant: tenant, integration: integration, name: "lead_distribution_alert_v2")

      expect(template).to be_persisted
      expect(template.clean_buttons).to eq([{ "kind" => "quick_reply", "text" => "Salvar contato" }])
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
