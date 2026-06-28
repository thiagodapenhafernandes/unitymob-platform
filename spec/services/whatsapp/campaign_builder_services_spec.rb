require "rails_helper"

RSpec.describe "WhatsApp campaign builder services" do
  let(:admin) { create(:admin_user, :admin) }
  let(:template) do
    WhatsappTemplate.create!(
      name: "lead_nurture",
      language: "pt_BR",
      status: "APPROVED",
      body: "Oi {{1}}, origem {{2}}."
    )
  end

  describe Whatsapp::CampaignAudiencePreview do
    it "conta audiencia filtrada separando leads com e sem telefone" do
      create(:lead, name: "Lead A", phone: "(47) 99999-0000", origin: "site", status: "Novo", admin_user: admin)
      without_phone = create(:lead, phone: "(47) 98888-0000", origin: "site", status: "Novo", admin_user: admin)
      without_phone.update_column(:phone, nil)
      create(:lead, phone: "(47) 97777-0000", origin: "portal", status: "Novo", admin_user: admin)

      result = described_class.call(filters: { status: "Novo", origin: "site", admin_user_id: admin.id })

      expect(result.total).to eq(2)
      expect(result.valid_phone_count).to eq(1)
      expect(result.without_phone_count).to eq(1)
      expect(result.sample.map(&:display_name)).to include("Lead A")
    end
  end

  describe Whatsapp::CampaignAudienceResolver do
    it "resolve publico por condicoes dinamicas" do
      create(:lead, name: "Lead A", phone: "(47) 99999-0000", origin: "site", status: "Novo", admin_user: admin)
      create(:lead, phone: "(47) 98888-0000", origin: "portal", status: "Novo", admin_user: admin)

      campaign = WhatsappCampaign.new(
        name: "Preview",
        whatsapp_template: template,
        created_by: admin,
        audience_mode: "filters",
        audience_definition: {
          logic: "and",
          conditions: [
            { field: "status", operator: "equals", value: "Novo" },
            { field: "origin", operator: "contains", value: "site" }
          ]
        }
      )

      result = described_class.call(campaign)

      expect(result).to be_ok
      expect(result.valid_phone_count).to eq(1)
      expect(result.sample.map(&:display_name)).to include("Lead A")
    end

    it "resolve publico por status, origem e tags em selecao multipla" do
      create(:lead, name: "Lead A", phone: "(47) 99999-0000", origin: "site", status: "Novo", tags: ["Produto", "Premium"], admin_user: admin)
      create(:lead, phone: "(47) 98888-0000", origin: "portal", status: "Novo", tags: ["Produto"], admin_user: admin)
      create(:lead, phone: "(47) 97777-0000", origin: "site", status: "Descartado", tags: ["Premium"], admin_user: admin)

      campaign = WhatsappCampaign.new(
        name: "Preview",
        whatsapp_template: template,
        created_by: admin,
        audience_mode: "filters",
        audience_definition: {
          logic: "and",
          conditions: [
            { field: "status", operator: "in", values: ["Novo"] },
            { field: "origin", operator: "in", values: ["site"] },
            { field: "tags", operator: "with_any", values: ["Premium"] }
          ]
        }
      )

      result = described_class.call(campaign)

      expect(result).to be_ok
      expect(result.valid_phone_count).to eq(1)
      expect(result.sample.map(&:display_name)).to eq(["Lead A"])
    end

    it "limita amostra do preview em quatro leads" do
      6.times do |index|
        create(:lead, name: "Lead #{index}", phone: "(47) 99999-000#{index}", origin: "site", status: "Novo", admin_user: admin)
      end

      campaign = WhatsappCampaign.new(
        name: "Preview",
        whatsapp_template: template,
        created_by: admin,
        audience_mode: "filters",
        audience_definition: {
          logic: "and",
          conditions: [
            { field: "status", operator: "in", values: ["Novo"] }
          ]
        }
      )

      result = described_class.call(campaign)

      expect(result.valid_phone_count).to eq(6)
      expect(result.sample.size).to eq(4)
    end

    it "pre-visualiza arquivo CSV sem materializar leads" do
      file = Tempfile.new(["leads", ".csv"])
      file.write("nome,telefone,email,origem,status\nMaria Silva,11999990000,maria@example.com,importacao,Novo\nSem Telefone,,sem@example.com,importacao,Novo\n")
      file.rewind
      upload = Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: "leads.csv")
      campaign = WhatsappCampaign.new(
        name: "Preview CSV",
        whatsapp_template: template,
        created_by: admin,
        audience_mode: "spreadsheet"
      )

      result = described_class.call(campaign, uploaded_file: upload)

      expect(result).to be_ok
      expect(result.total).to eq(2)
      expect(result.valid_phone_count).to eq(1)
      expect(result.invalid_count).to eq(1)
      expect(result.sample.first.display_name).to eq("Maria Silva")
      expect(Lead.where(email: "maria@example.com")).not_to exist
    ensure
      file&.close!
    end

    it "materializa CSV como destinatario da campanha sem criar lead" do
      file = Tempfile.new(["leads", ".csv"])
      file.write("nome,telefone,email,origem,status,tags,responsavel_email\nMaria Silva,11999990000,maria@example.com,importacao,Novo,\"['Produto', 'Premium' 05]\",#{admin.email}\n")
      file.rewind
      upload = Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: "leads.csv")
      campaign = WhatsappCampaign.new(
        name: "Preview CSV",
        whatsapp_template: template,
        created_by: admin,
        audience_mode: "spreadsheet"
      )
      campaign.audience_file.attach(upload)
      campaign.save!
      file.rewind

      result = described_class.call(campaign, materialize: true, uploaded_file: upload)

      expect(result).to be_ok
      recipient = campaign.campaign_recipients.find_by!(email: "maria@example.com")
      expect(recipient.tags).to eq(["Produto", "Premium 05"])
      expect(recipient.admin_user_id).to eq(admin.id)
      expect(recipient.lead_id).to be_nil
      expect(Lead.where(email: "maria@example.com")).not_to exist
    ensure
      file&.close!
    end
  end

  describe Whatsapp::CampaignTemplatePreview do
    it "renderiza corpo do modelo usando variaveis e amostras" do
      result = described_class.call(template: template, variables: { "1" => "{{nome}}", "2" => "{{origem}}" })

      expect(result.body).to eq("Oi Maria Lead, origem site.")
      expect(result.values).to eq(["Maria Lead", "site"])
    end
  end

  describe Whatsapp::TemplateMessageComponents do
    it "monta parametros para cabecalho, corpo e URL dinamica" do
      component_template = WhatsappTemplate.new(
        name: "preambulos_envio",
        language: "pt_BR",
        status: "APPROVED",
        template_type: "text",
        components: [
          { "type" => "HEADER", "format" => "TEXT", "text" => "Oferta para {{1}}" },
          { "type" => "BODY", "text" => "Olá {{2}}, veja as condições." },
          { "type" => "BUTTONS", "buttons" => [{ "type" => "URL", "text" => "Abrir", "url" => "https://example.com/{{3}}" }] }
        ]
      )

      result = described_class.call(
        template: component_template,
        variables: { "1" => "Premium", "2" => "Maria", "3" => "maria-123" }
      )

      expect(result).to be_ok
      expect(result.components).to eq(
        [
          { type: "header", parameters: [{ type: "text", text: "Premium" }] },
          { type: "body", parameters: [{ type: "text", text: "Maria" }] },
          { type: "button", sub_type: "url", index: "0", parameters: [{ type: "text", text: "maria-123" }] }
        ]
      )
    end
  end

  describe Whatsapp::CampaignTestSender do
    it "envia template de teste pela Cloud API" do
      create(:whatsapp_business_integration, connected_by_admin_user: admin)
      client = instance_double(Whatsapp::CloudClient)
      allow(Whatsapp::CloudClient).to receive(:new).and_return(client)
      allow(client).to receive(:send_template).and_return({ ok: true, message_id: "wamid.test" })

      result = described_class.call(template: template, phone: "(47) 99999-0000", variables: { "1" => "{{nome}}", "2" => "{{origem}}" })

      expect(result).to include(ok: true, message_id: "wamid.test", delivery_status: "sent")
      expect(result[:delivery_hint]).to include("webhook de status")
      outbound = WhatsappMessage.find(result[:whatsapp_message_id])
      expect(outbound).to have_attributes(
        direction: "outbound",
        msg_type: "template",
        template_name: "lead_nurture",
        status: "sent",
        wa_message_id: "wamid.test"
      )
      expect(outbound.whatsapp_conversation.contact_phone).to eq("5547999990000")
      expect(client).to have_received(:send_template).with(
        hash_including(
          to: "5547999990000",
          name: "lead_nurture",
          language: "pt_BR"
        )
      )
    end

    it "envia cabecalho de midia quando o modelo aprovado exige imagem" do
      media_template = WhatsappTemplate.create!(
        name: "campanha_fake",
        language: "pt_BR",
        status: "APPROVED",
        template_type: "text",
        header_format: "image",
        header_media_handle: "https://cdn.example.test/header.png",
        body: "Escolha uma das opções abaixo.",
        components: [
          {
            "type" => "HEADER",
            "format" => "IMAGE",
            "example" => { "header_handle" => ["https://cdn.example.test/header.png"] }
          },
          { "type" => "BODY", "text" => "Escolha uma das opções abaixo." },
          {
            "type" => "BUTTONS",
            "buttons" => [
              { "type" => "QUICK_REPLY", "text" => "Saiba mais" }
            ]
          }
        ]
      )
      sender = create(:whatsapp_sender_number)
      client = instance_double(Whatsapp::CloudClient)
      allow(Whatsapp::CloudClient).to receive(:new).with(sender).and_return(client)
      allow(client).to receive(:send_template).and_return({ ok: true, message_id: "wamid.media" })

      result = described_class.call(template: media_template, phone: "21990872427", variables: {}, sender_number: sender)

      expect(result).to include(ok: true, message_id: "wamid.media")
      expect(client).to have_received(:send_template).with(
        hash_including(
          name: "campanha_fake",
          components: [
            {
              type: "header",
              parameters: [
                { type: "image", image: { link: "https://cdn.example.test/header.png" } }
              ]
            }
          ]
        )
      )
    end

    it "preserva detalhes da Meta e orienta quando o formato do template nao confere" do
      sender = create(:whatsapp_sender_number)
      client = instance_double(Whatsapp::CloudClient)
      allow(Whatsapp::CloudClient).to receive(:new).with(sender).and_return(client)
      allow(client).to receive(:send_template).and_return(
        {
          ok: false,
          error: "(#132012) Parameter format does not match format in the created template.",
          meta_error: { code: 132012, type: "OAuthException", trace_id: "ABC123" }
        }
      )

      result = described_class.call(template: template, phone: "21990872427", variables: {}, sender_number: sender)

      expect(result).to include(
        ok: false,
        error: "(#132012) Parameter format does not match format in the created template.",
        meta_error: { code: 132012, type: "OAuthException", trace_id: "ABC123" }
      )
      expect(result[:error_hint]).to include("formato enviado não corresponde ao template aprovado")
      expect(WhatsappMessage.last).to have_attributes(
        direction: "outbound",
        msg_type: "template",
        template_name: "lead_nurture",
        status: "failed"
      )
      expect(WhatsappMessage.last.error_message).to include("#132012")
    end
  end
end
