require "rails_helper"

RSpec.describe Whatsapp::LeadActivationTemplate do
  describe ".for" do
    it "usa rodapé neutro no template para nao fixar dados de conta" do
      tenant = Tenant.create!(name: "Imobiliária Atlântico", slug: "imobiliaria-atlantico-#{SecureRandom.hex(3)}")
      integration = WhatsappBusinessIntegration.current(tenant)
      integration.update!(waba_id: "waba-atlantico")

      template = described_class.for(tenant: tenant, integration: integration)

      expect(template.name).to eq("lead_activation_default")
      expect(template.header_format).to eq("image")
      expect(template.footer_text).to eq("Atendimento")
      expect(template.footer_text).not_to include("Conexão")
      expect(template.footer_text).not_to include("Imobiliária Atlântico")
    end

    it "substitui rodapé fixo legado quando o template ainda é editável" do
      tenant = Tenant.create!(name: "Salute Imóveis", slug: "salute-imoveis-#{SecureRandom.hex(3)}")
      integration = WhatsappBusinessIntegration.current(tenant)
      integration.update!(waba_id: "waba-salute")
      template = tenant.whatsapp_templates.create!(
        name: described_class::TEMPLATE_NAME,
        language: described_class::LANGUAGE,
        waba_id: integration.waba_id,
        status: "DRAFT",
        template_type: "text",
        category: "MARKETING",
        header_format: "image",
        body: described_class::DEFAULT_BODY,
        footer_text: "Atendimento Conexão"
      )

      resolved = described_class.for(tenant: tenant, integration: integration)

      expect(resolved.id).to eq(template.id)
      expect(resolved.footer_text).to eq("Atendimento")
    end

    it "monta payload de aprovacao com cabecalho de imagem" do
      tenant = Tenant.create!(name: "Imagem Modelo", slug: "imagem-modelo-#{SecureRandom.hex(3)}")
      integration = WhatsappBusinessIntegration.current(tenant)
      integration.update!(waba_id: "waba-imagem-modelo")
      template = described_class.for(tenant: tenant, integration: integration)
      template.header_media_handle = "header-handle"

      expect(template.meta_create_payload[:components]).to include(
        type: "HEADER",
        format: "IMAGE",
        example: { header_handle: ["header-handle"] }
      )
    end

    it "reaproveita a imagem aprovada anterior ao montar rascunho para a WABA conectada atual" do
      tenant = Tenant.create!(name: "Conexão Atual", slug: "conexao-atual-#{SecureRandom.hex(3)}")
      old_integration = WhatsappBusinessIntegration.current(tenant)
      old_integration.update!(waba_id: "waba-antiga")
      approved_template = tenant.whatsapp_templates.create!(
        name: described_class::TEMPLATE_NAME,
        language: described_class::LANGUAGE,
        waba_id: old_integration.waba_id,
        status: "APPROVED",
        template_type: "text",
        category: "MARKETING",
        header_format: "image",
        header_media_handle: "old-handle",
        body: "Oi {{1}}, aqui é {{2}}",
        footer_text: "Atendimento"
      )
      approved_template.header_media_file.attach(
        io: StringIO.new("fake-image"),
        filename: "apresentacao.jpg",
        content_type: "image/jpeg"
      )
      current_integration = WhatsappBusinessIntegration.current(tenant)
      current_integration.update!(waba_id: "waba-atual")

      template = described_class.for(tenant: tenant, integration: current_integration)

      expect(template).to be_new_record
      expect(template.waba_id).to eq("waba-atual")
      expect(template.header_media_file).to be_attached
      expect(template.header_media_file.blob).to eq(approved_template.header_media_file.blob)
      expect(template.body).to eq("Oi {{1}}, aqui é {{2}}")
    end
  end
end
