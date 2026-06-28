require "rails_helper"

RSpec.describe "Webhooks::Whatsapp", type: :request do
  before { host! "localhost" }

  let!(:integration) do
    integ = WhatsappBusinessIntegration.current
    integ.save!
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
      conv = WhatsappConversation.create!(contact_phone: "5547888880000")
      msg = conv.messages.create!(direction: "outbound", wa_message_id: "wamid.OUT1", status: "sent")

      status_payload = {
        entry: [{ changes: [{ value: { statuses: [{ id: "wamid.OUT1", status: "read", timestamp: "1700000500" }] } }] }]
      }
      post "/webhooks/whatsapp", params: status_payload, as: :json

      expect(msg.reload.status).to eq("read")
      expect(msg.read_at).to be_present
    end

    it "registra aceite Meta em mensagem de campanha quando chega status sent" do
      admin = create(:admin_user, :admin)
      template = WhatsappTemplate.create!(name: "campanha_status", language: "pt_BR", status: "APPROVED", body: "Oi")
      campaign = WhatsappCampaign.create!(name: "Campanha status", whatsapp_template: template, created_by: admin, status: "processing")
      conv = WhatsappConversation.create!(contact_phone: "5547888880000")
      outbound = conv.messages.create!(direction: "outbound", wa_message_id: "wamid.OUT2", status: "pending")
      campaign_message = campaign.campaign_messages.create!(
        phone_number: "5547888880000",
        status: "queued",
        external_message_id: "wamid.OUT2",
        whatsapp_message: outbound
      )

      post "/webhooks/whatsapp", params: {
        entry: [{ changes: [{ value: { statuses: [{ id: "wamid.OUT2", status: "sent", timestamp: "1700000500" }] } }] }]
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(outbound.reload.status).to eq("sent")
      expect(campaign_message.reload.status).to eq("sent")
      expect(campaign_message.status_label).to eq("Aceita pela Meta")
      expect(campaign_message.sent_at).to be_present
      expect(campaign.reload.sent_count).to eq(1)
    end

    it "converte recipient em lead somente quando botao configurado pede conversao" do
      admin = create(:admin_user, :admin)
      rule = create(:distribution_rule)
      template = WhatsappTemplate.create!(
        name: "campanha_resposta",
        language: "pt_BR",
        status: "APPROVED",
        body: "Escolha",
        buttons: { "0" => { "kind" => "quick_reply", "text" => "Quero atendimento" } }
      )
      button = template.interactive_buttons.first
      campaign = WhatsappCampaign.create!(
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

    it "registra reprovação de template pelo webhook de status da Meta" do
      template = WhatsappTemplate.create!(
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
