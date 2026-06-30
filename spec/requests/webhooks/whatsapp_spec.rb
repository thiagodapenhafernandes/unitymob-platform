require "rails_helper"

RSpec.describe "Webhooks::Whatsapp", type: :request do
  around do |example|
    previous_tenant = Current.tenant
    Current.tenant = Tenant.default
    example.run
  ensure
    Current.tenant = previous_tenant
  end

  before { host! "localhost" }

  let!(:integration) do
    integ = WhatsappBusinessIntegration.current(Tenant.default)
    integ.update!(
      status: "connected",
      phone_number_id: "phone-default-#{SecureRandom.hex(3)}",
      waba_id: "waba-default-#{SecureRandom.hex(3)}",
      access_token: "token",
      default_whatsapp_number: "554733111067"
    )
    integ.webhook_verify_token!
    integ
  end

  describe "GET /webhooks/whatsapp (verificação)" do
    it "responde o challenge quando o token confere" do
      get "/webhooks/whatsapp", params: {
        "hub.mode" => "subscribe",
        "hub.verify_token" => integration.webhook_verify_token,
        "hub.challenge" => "123456"
      }
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("123456")
    end

    it "recusa token inválido" do
      get "/webhooks/whatsapp", params: { "hub.mode" => "subscribe", "hub.verify_token" => "errado", "hub.challenge" => "x" }
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /webhooks/whatsapp (recebimento)" do
    let(:payload) do
      {
        object: "whatsapp_business_account",
        entry: [{
          id: "WABA",
          changes: [{
            field: "messages",
            value: {
              messaging_product: "whatsapp",
              metadata: { phone_number_id: integration.phone_number_id },
              contacts: [{ profile: { name: "Maria Silva" }, wa_id: "5547999990000" }],
              messages: [{
                from: "5547999990000",
                id: "wamid.TEST123",
                timestamp: "1700000000",
                type: "text",
                text: { body: "Tenho interesse no ap 302" }
              }]
            }
          }]
        }]
      }
    end

    it "cria conversa, mensagem, lead e atividade na timeline" do
      expect {
        post "/webhooks/whatsapp", params: payload, as: :json
      }.to change(WhatsappConversation, :count).by(1)
       .and change(WhatsappMessage, :count).by(1)
       .and change(Lead, :count).by(1)

      expect(response).to have_http_status(:ok)
      conv = WhatsappConversation.last
      expect(conv.contact_phone).to eq("5547999990000")
      expect(conv.contact_name).to eq("Maria Silva")
      expect(conv.unread_count).to eq(1)
      expect(conv.lead).to be_present
      expect(conv.lead.origin).to eq("whatsapp")
      expect(conv.messages.last.body).to include("ap 302")
      expect(conv.lead.activities.where(kind: "whatsapp_in").count).to eq(1)
    end

    it "não duplica mensagem já recebida (dedup por wa_message_id)" do
      post "/webhooks/whatsapp", params: payload, as: :json
      expect {
        post "/webhooks/whatsapp", params: payload, as: :json
      }.not_to change(WhatsappMessage, :count)
    end

    it "atualiza status de mensagem enviada" do
      conv = WhatsappConversation.create!(tenant: integration.tenant, contact_phone: "5547888880000")
      msg = conv.messages.create!(direction: "outbound", wa_message_id: "wamid.OUT1", status: "sent")

      status_payload = {
        entry: [{ changes: [{ value: { metadata: { phone_number_id: integration.phone_number_id }, statuses: [{ id: "wamid.OUT1", status: "read", timestamp: "1700000500" }] } }] }]
      }
      post "/webhooks/whatsapp", params: status_payload, as: :json

      expect(msg.reload.status).to eq("read")
      expect(msg.read_at).to be_present
    end

    it "registra aceite Meta em mensagem de campanha quando chega status sent" do
      admin = create(:admin_user, :admin)
      template = WhatsappTemplate.create!(tenant: admin.tenant, name: "campanha_status", language: "pt_BR", status: "APPROVED", body: "Oi")
      campaign = WhatsappCampaign.create!(tenant: admin.tenant, name: "Campanha status", whatsapp_template: template, created_by: admin, status: "processing")
      conv = WhatsappConversation.create!(tenant: admin.tenant, contact_phone: "5547888880000")
      outbound = conv.messages.create!(direction: "outbound", wa_message_id: "wamid.OUT2", status: "pending")
      campaign_message = campaign.campaign_messages.create!(
        phone_number: "5547888880000",
        status: "queued",
        external_message_id: "wamid.OUT2",
        whatsapp_message: outbound
      )

      post "/webhooks/whatsapp", params: {
        entry: [{ changes: [{ value: { metadata: { phone_number_id: integration.phone_number_id }, statuses: [{ id: "wamid.OUT2", status: "sent", timestamp: "1700000500" }] } }] }]
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(outbound.reload.status).to eq("sent")
      expect(campaign_message.reload.status).to eq("sent")
      expect(campaign_message.status_label).to eq("Enviado")
      expect(campaign_message.sent_at).to be_present
      expect(campaign.reload.sent_count).to eq(1)
    end

    it "atualiza status de campanha apenas no tenant resolvido pelo numero do webhook" do
      current_admin = create(:admin_user, :admin)
      other_tenant = Tenant.create!(name: "Outro WhatsApp #{SecureRandom.hex(3)}", slug: "outro-whatsapp-#{SecureRandom.hex(3)}")
      other_admin = create(:admin_user, :admin, tenant: other_tenant)
      current_integration = WhatsappBusinessIntegration.current(current_admin.tenant)
      current_integration.update!(status: "connected", phone_number_id: "phone-current-#{SecureRandom.hex(3)}", waba_id: "waba-current-#{SecureRandom.hex(3)}", access_token: "token")
      create(
        :whatsapp_sender_number,
        tenant: current_admin.tenant,
        whatsapp_business_integration: current_integration,
        phone_number_id: current_integration.phone_number_id,
        waba_id: current_integration.waba_id,
        display_phone_number: "5511999990000"
      )
      current_template = WhatsappTemplate.create!(tenant: current_admin.tenant, name: "campanha_status_tenant", language: "pt_BR", status: "APPROVED", body: "Oi")
      other_template = WhatsappTemplate.create!(tenant: other_tenant, name: "campanha_status_tenant", language: "pt_BR", status: "APPROVED", body: "Oi")
      current_campaign = WhatsappCampaign.create!(tenant: current_admin.tenant, name: "Campanha atual", whatsapp_template: current_template, created_by: current_admin, status: "processing")
      other_campaign = WhatsappCampaign.create!(tenant: other_tenant, name: "Campanha externa", whatsapp_template: other_template, created_by: other_admin, status: "processing")
      current_conversation = WhatsappConversation.create!(tenant: current_admin.tenant, contact_phone: "5547888880000")
      other_conversation = WhatsappConversation.create!(tenant: other_tenant, contact_phone: "5547888880000")
      current_message = current_conversation.messages.create!(direction: "outbound", wa_message_id: "wamid.SHARED", status: "pending")
      other_message = other_conversation.messages.create!(direction: "outbound", wa_message_id: "wamid.SHARED", status: "pending")
      current_campaign_message = current_campaign.campaign_messages.create!(
        phone_number: "5547888880000",
        status: "queued",
        external_message_id: "wamid.SHARED",
        whatsapp_message: current_message
      )
      other_campaign_message = other_campaign.campaign_messages.create!(
        phone_number: "5547888880000",
        status: "queued",
        external_message_id: "wamid.SHARED",
        whatsapp_message: other_message
      )

      post "/webhooks/whatsapp", params: {
        entry: [{
          changes: [{
            value: {
              metadata: { phone_number_id: current_integration.phone_number_id },
              statuses: [{ id: "wamid.SHARED", status: "sent", timestamp: "1700000500" }]
            }
          }]
        }]
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(current_message.reload.status).to eq("sent")
      expect(current_campaign_message.reload.status).to eq("sent")
      expect(other_message.reload.status).to eq("pending")
      expect(other_campaign_message.reload.status).to eq("queued")
    end

    it "ignora status sem metadados quando o wamid existe em mais de um tenant" do
      current_tenant = Tenant.default
      other_tenant = Tenant.create!(name: "Outro status ambíguo #{SecureRandom.hex(3)}", slug: "outro-status-ambiguo-#{SecureRandom.hex(3)}")
      current_conversation = WhatsappConversation.create!(tenant: current_tenant, contact_phone: "5547888880000")
      other_conversation = WhatsappConversation.create!(tenant: other_tenant, contact_phone: "5547888880000")
      current_message = current_conversation.messages.create!(direction: "outbound", wa_message_id: "wamid.AMBIGUO", status: "sent")
      other_message = other_conversation.messages.create!(direction: "outbound", wa_message_id: "wamid.AMBIGUO", status: "sent")

      post "/webhooks/whatsapp", params: {
        entry: [{ changes: [{ value: { statuses: [{ id: "wamid.AMBIGUO", status: "read", timestamp: "1700000500" }] } }] }]
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(current_message.reload.status).to eq("sent")
      expect(other_message.reload.status).to eq("sent")
    end

    it "converte recipient em lead somente quando botao configurado pede conversao" do
      admin = create(:admin_user, :admin)
      rule = create(:distribution_rule, tenant: admin.tenant)
      template = WhatsappTemplate.create!(
        tenant: admin.tenant,
        name: "campanha_resposta",
        language: "pt_BR",
        status: "APPROVED",
        body: "Escolha",
        buttons: { "0" => { "kind" => "quick_reply", "text" => "Quero atendimento" } }
      )
      button = template.interactive_buttons.first
      campaign = WhatsappCampaign.create!(
        tenant: admin.tenant,
        name: "Campanha com conversao",
        whatsapp_template: template,
        created_by: admin,
        status: "processing",
        response_decisions: {
          buttons: [{
            key: button["key"],
            text: button["text"],
            kind: button["kind"],
            action: "generate_lead",
            distribution_rule_id: rule.id
          }]
        }
      )
      recipient = campaign.campaign_recipients.create!(
        name: "Maria Importada",
        phone_number: "5547999990000",
        email: "maria@example.com",
        origin: "planilha",
        source: "spreadsheet"
      )
      campaign.campaign_messages.create!(
        whatsapp_campaign_recipient: recipient,
        phone_number: recipient.phone_number,
        status: "sent",
        external_message_id: "wamid.OUT3"
      )

      expect {
        post "/webhooks/whatsapp", params: {
          object: "whatsapp_business_account",
          entry: [{
            changes: [{
              field: "messages",
              value: {
                metadata: { phone_number_id: integration.phone_number_id },
                contacts: [{ profile: { name: "Maria Importada" }, wa_id: recipient.phone_number }],
                messages: [{
                  from: recipient.phone_number,
                  id: "wamid.IN3",
                  timestamp: "1700000600",
                  type: "button",
                  button: { text: "Quero atendimento", payload: button["key"] }
                }]
              }
            }]
          }]
        }, as: :json
      }.to change(Lead, :count).by(1)

      expect(response).to have_http_status(:ok)
      converted_lead = recipient.reload.lead
      expect(converted_lead).to be_present
      expect(converted_lead.tenant).to eq(campaign.tenant)
      expect(converted_lead.origin).to eq("planilha")
      expect(converted_lead.distribution_rule).to eq(rule)
      expect(recipient.conversion_status).to eq("converted")
      expect(campaign.campaign_messages.last.reload.lead).to eq(converted_lead)
      expect(WhatsappConversation.last.lead).to eq(converted_lead)
      expect(converted_lead.activities.where(kind: "whatsapp_campaign_conversion").count).to eq(1)
      expect(converted_lead.activities.where(kind: "whatsapp_in").count).to eq(1)
    end

    it "aprova template automaticamente pelo webhook de status da Meta" do
      template = WhatsappTemplate.create!(
        tenant: integration.tenant,
        name: "campanha_fake",
        language: "pt_BR",
        status: "PENDING",
        meta_id: "997629813160309",
        category: "MARKETING",
        body: "Olá"
      )

      post "/webhooks/whatsapp", params: {
        entry: [{
          changes: [{
            field: "message_template_status_update",
            value: {
              whatsapp_business_account_id: integration.waba_id,
              message_template_id: "997629813160309",
              message_template_name: "campanha_fake",
              message_template_language: "pt_BR",
              event: "APPROVED"
            }
          }]
        }]
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(template.reload.status).to eq("APPROVED")
      expect(template.submission_error).to be_nil
    end

    it "ignora status de template sem metadados quando o meta_id existe em mais de um tenant" do
      other_tenant = Tenant.create!(name: "Outro template ambíguo #{SecureRandom.hex(3)}", slug: "outro-template-ambiguo-#{SecureRandom.hex(3)}")
      current_template = WhatsappTemplate.create!(
        name: "campanha_ambigua",
        language: "pt_BR",
        status: "PENDING",
        meta_id: "META-AMBIGUO",
        category: "MARKETING",
        body: "Olá"
      )
      other_template = WhatsappTemplate.create!(
        tenant: other_tenant,
        name: "campanha_ambigua",
        language: "pt_BR",
        status: "PENDING",
        meta_id: "META-AMBIGUO",
        category: "MARKETING",
        body: "Olá"
      )

      post "/webhooks/whatsapp", params: {
        entry: [{
          changes: [{
            field: "message_template_status_update",
            value: {
              message_template_id: "META-AMBIGUO",
              message_template_name: "campanha_ambigua",
              message_template_language: "pt_BR",
              event: "APPROVED"
            }
          }]
        }]
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(current_template.reload.status).to eq("PENDING")
      expect(other_template.reload.status).to eq("PENDING")
    end

    it "registra reprovação de template pelo webhook de status da Meta" do
      template = WhatsappTemplate.create!(
        tenant: integration.tenant,
        name: "campanha_reprovada",
        language: "pt_BR",
        status: "PENDING",
        category: "MARKETING",
        body: "Olá"
      )

      post "/webhooks/whatsapp", params: {
        entry: [{
          changes: [{
            field: "message_template_status_update",
            value: {
              whatsapp_business_account_id: integration.waba_id,
              message_template_name: "campanha_reprovada",
              message_template_language: "pt_BR",
              event: "REJECTED",
              reason: "INVALID_FORMAT"
            }
          }]
        }]
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(template.reload.status).to eq("REJECTED")
      expect(template.submission_error).to eq("INVALID_FORMAT")
    end
  end
end
