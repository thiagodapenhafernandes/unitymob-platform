require "rails_helper"

RSpec.describe Whatsapp::ThreadBroadcaster do
  def create_tenant!(suffix)
    Tenant.create!(name: "Tenant #{suffix}", slug: "tenant-#{suffix}", active: true)
  end

  describe ".message_created" do
    it "broadcasta a mensagem renderizada e a fila atualizada da conversa" do
      tenant = create_tenant!("wa-1")
      lead = create(:lead, tenant: tenant, name: "Lead WhatsApp")
      conversation = WhatsappConversation.create!(tenant: tenant, lead: lead, contact_phone: "5547999990011", contact_name: "Maria")
      conversation.messages.create!(direction: "inbound", body: "primeira", status: "delivered", created_at: 2.minutes.ago)
      message = conversation.messages.create!(direction: "inbound", body: "Olá", status: "delivered")
      conversation.touch_last_message!(message)

      calls = []
      allow(ActionCable.server).to receive(:broadcast) do |stream, payload|
        calls << [stream, payload]
      end

      described_class.message_created(message)

      expect(calls.size).to eq(2)

      default_call = calls.find { |stream, _payload| stream == "whatsapp_conversation:#{conversation.tenant_id}:#{conversation.id}:default" }
      focus_call = calls.find { |stream, _payload| stream == "whatsapp_conversation:#{conversation.tenant_id}:#{conversation.id}:focus" }

      expect(default_call).to be_present
      expect(focus_call).to be_present

      default_payload = default_call.last
      expect(default_payload.dig(:messages, 0, :id)).to eq(message.id)
      expect(default_payload.dig(:messages, 0, :html)).to include("Olá")
      expect(default_payload.dig(:messages, 0, :html)).to include("wa-inbox-bubble--compact")
      expect(default_payload.dig(:updates, 0, :html)).to include("primeira")
      expect(default_payload.dig(:queue, :html)).to include("Maria")
      expect(default_payload[:status_cursor]).to be_present
      expect(default_payload.dig(:context_fragments, :summary_html)).to include("Última atividade")
      expect(default_payload.dig(:context_fragments, :crm_copy_html)).to include("CRM comercial")

      focus_payload = focus_call.last
      expect(focus_payload.dig(:messages, 0, :id)).to eq(message.id)
      expect(focus_payload.dig(:messages, 0, :html)).to include("wa-inbox-bubble--compact")
      expect(focus_payload.dig(:context_fragments, :crm_copy_html)).to include("<strong>CRM</strong>")
    end
  end

  describe ".message_updated" do
    it "broadcasta update de status sem duplicar fila" do
      conversation = WhatsappConversation.create!(tenant: create_tenant!("wa-2"), contact_phone: "5547999990012")
      message = conversation.messages.create!(direction: "outbound", body: "Teste", status: "read")

      calls = []
      allow(ActionCable.server).to receive(:broadcast) do |stream, payload|
        calls << [stream, payload]
      end

      described_class.message_updated(message)

      expect(calls.size).to eq(2)
      default_payload = calls.find { |stream, _payload| stream == "whatsapp_conversation:#{conversation.tenant_id}:#{conversation.id}:default" }&.last

      expect(default_payload).to be_present
      expect(default_payload.dig(:updates, 0, :id)).to eq(message.id)
      expect(default_payload.dig(:updates, 0, :status)).to eq("read")
      expect(default_payload.dig(:updates, 0, :html)).to include('data-wa-message-status="read"')
      expect(default_payload.dig(:updates, 0, :html)).to include("data-wa-message-status-icon")
      expect(default_payload.dig(:updates, 0, :html)).to include('title="Lida"')
      expect(default_payload.dig(:updates, 0, :html)).to include("is-read")
      expect(default_payload.dig(:updates, 0, :html)).to include("wa-inbox-bubble--compact")
      expect(default_payload.dig(:context_fragments, :summary_html)).to include("Última atividade")
    end
  end
end
