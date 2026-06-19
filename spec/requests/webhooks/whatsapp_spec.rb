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
  end
end
