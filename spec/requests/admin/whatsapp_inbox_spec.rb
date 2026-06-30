require "rails_helper"

RSpec.describe "Admin::WhatsappInbox", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "wa-#{SecureRandom.hex(6)}@salute.test") }

  before do
    host! "localhost"
    sign_in admin
  end

  describe "GET index" do
    it "exibe a central de atendimento" do
      WhatsappConversation.create!(contact_phone: "5547999990000", contact_name: "Maria", last_message_preview: "Olá", unread_count: 2)

      get admin_whatsapp_conversations_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Atendimento WhatsApp")
      expect(response.body).to include("Maria")
    end
  end

  describe "GET show" do
    it "abre a conversa e zera não lidas" do
      conv = WhatsappConversation.create!(contact_phone: "5547999990000", unread_count: 3)
      conv.messages.create!(direction: "inbound", body: "Tem disponível?", status: "delivered")

      get admin_whatsapp_conversation_path(conv)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Tem disponível?")
      expect(conv.reload.unread_count).to eq(0)
    end
  end

  describe "POST send_message" do
    it "cria mensagem outbound, registra na timeline e enfileira envio" do
      allow(Whatsapp::SendMessageJob).to receive(:perform_later)
      lead = create(:lead)
      conv = WhatsappConversation.create!(contact_phone: "5547999990000", lead: lead)

      expect {
        post send_message_admin_whatsapp_conversation_path(conv), params: { body: "Olá, posso ajudar?" }
      }.to change { conv.messages.outbound.count }.by(1)

      msg = conv.messages.outbound.last
      expect(msg.body).to eq("Olá, posso ajudar?")
      expect(msg.status).to eq("pending")
      expect(Whatsapp::SendMessageJob).to have_received(:perform_later).with(msg.id, tenant_id: msg.tenant_id)
      expect(lead.activities.where(kind: "whatsapp_out").count).to eq(1)
    end
  end

  describe "POST messages (polling json)" do
    it "retorna mensagens novas após o id informado" do
      conv = WhatsappConversation.create!(contact_phone: "5547999990000")
      m1 = conv.messages.create!(direction: "inbound", body: "primeira", status: "delivered")
      m2 = conv.messages.create!(direction: "inbound", body: "segunda", status: "delivered")

      get messages_admin_whatsapp_conversation_path(conv, after: m1.id), headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data.map { |m| m["id"] }).to eq([m2.id])
    end
  end
end
