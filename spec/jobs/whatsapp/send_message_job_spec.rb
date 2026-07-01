require "rails_helper"

RSpec.describe Whatsapp::SendMessageJob, type: :job do
  let(:tenant) { Tenant.default }

  describe ".dispatch" do
    it "executa inline em development quando não há override explícito" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("WHATSAPP_SEND_INLINE").and_return("")
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
      allow(described_class).to receive(:perform_now)
      allow(described_class).to receive(:perform_later)

      described_class.dispatch(123, tenant_id: tenant.id)

      expect(described_class).to have_received(:perform_now).with(123, tenant_id: tenant.id)
      expect(described_class).not_to have_received(:perform_later)
    end

    it "enfileira fora de development quando não há override explícito" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("WHATSAPP_SEND_INLINE").and_return("")
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
      allow(described_class).to receive(:perform_now)
      allow(described_class).to receive(:perform_later)

      described_class.dispatch(123, tenant_id: tenant.id)

      expect(described_class).to have_received(:perform_later).with(123, tenant_id: tenant.id)
      expect(described_class).not_to have_received(:perform_now)
    end

    it "respeita override explícito para envio inline" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("WHATSAPP_SEND_INLINE").and_return("true")
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
      allow(described_class).to receive(:perform_now)
      allow(described_class).to receive(:perform_later)

      described_class.dispatch(123, tenant_id: tenant.id)

      expect(described_class).to have_received(:perform_now).with(123, tenant_id: tenant.id)
      expect(described_class).not_to have_received(:perform_later)
    end
  end

  describe "#perform" do
    it "broadcasta a transição para sent quando a Meta aceita o envio" do
      create(:whatsapp_business_integration, tenant: tenant)
      conversation = WhatsappConversation.create!(tenant: tenant, contact_phone: "5547999990044", status: "open")
      message = conversation.messages.create!(tenant: tenant, direction: "outbound", status: "pending", msg_type: "text", body: "Olá")
      client = instance_double(Whatsapp::CloudClient)
      allow(Whatsapp::CloudClient).to receive(:new).and_return(client)
      allow(client).to receive(:send_text).and_return({ ok: true, message_id: "wamid-ok-1" })
      allow(Whatsapp::ThreadBroadcaster).to receive(:message_updated)

      described_class.perform_now(message.id, tenant_id: tenant.id)

      expect(message.reload.status).to eq("sent")
      expect(message.wa_message_id).to eq("wamid-ok-1")
      expect(Whatsapp::ThreadBroadcaster).to have_received(:message_updated).with(message)
    end

    it "broadcasta a transição para failed quando o envio falha" do
      create(:whatsapp_business_integration, tenant: tenant)
      conversation = WhatsappConversation.create!(tenant: tenant, contact_phone: "5547999990045", status: "open")
      message = conversation.messages.create!(tenant: tenant, direction: "outbound", status: "pending", msg_type: "text", body: "Olá")
      client = instance_double(Whatsapp::CloudClient)
      allow(Whatsapp::CloudClient).to receive(:new).and_return(client)
      allow(client).to receive(:send_text).and_return({ ok: false, error: "forbidden" })
      allow(Whatsapp::ThreadBroadcaster).to receive(:message_updated)

      described_class.perform_now(message.id, tenant_id: tenant.id)

      expect(message.reload.status).to eq("failed")
      expect(message.error_message).to include("forbidden")
      expect(Whatsapp::ThreadBroadcaster).to have_received(:message_updated).with(message)
    end

    it "broadcasta failed quando a conversa não tem telefone nem BSUID" do
      create(:whatsapp_business_integration, tenant: tenant)
      conversation = WhatsappConversation.create!(tenant: tenant, contact_phone: "5547999990046", status: "open")
      conversation.update_columns(contact_phone: nil, business_scoped_user_id: nil)
      message = conversation.messages.create!(tenant: tenant, direction: "outbound", status: "pending", msg_type: "text", body: "Olá")
      allow(Whatsapp::ThreadBroadcaster).to receive(:message_updated)

      described_class.perform_now(message.id, tenant_id: tenant.id)

      expect(message.reload.status).to eq("failed")
      expect(message.error_message).to eq("Conversa sem telefone ou BSUID")
      expect(Whatsapp::ThreadBroadcaster).to have_received(:message_updated).with(message)
    end

    it "falha cedo para mídia anexada em formato inválido" do
      create(:whatsapp_business_integration, tenant: tenant)
      conversation = WhatsappConversation.create!(tenant: tenant, contact_phone: "5547999990042", status: "open")
      message = conversation.messages.create!(tenant: tenant, direction: "outbound", status: "pending", msg_type: "document", body: "Arquivo inválido")
      message.media_file.attach(io: StringIO.new("zip"), filename: "pacote.zip", content_type: "application/zip")
      client = instance_double(Whatsapp::CloudClient)
      allow(Whatsapp::CloudClient).to receive(:new).and_return(client)
      allow(client).to receive(:send_media)
      allow(client).to receive(:upload_message_media)

      described_class.perform_now(message.id, tenant_id: tenant.id)

      expect(message.reload.status).to eq("failed")
      expect(message.error_message).to include("Formato não suportado")
      expect(client).not_to have_received(:upload_message_media)
      expect(client).not_to have_received(:send_media)
    end

    it "falha cedo quando a mídia não tem anexo nem link remoto" do
      create(:whatsapp_business_integration, tenant: tenant)
      conversation = WhatsappConversation.create!(tenant: tenant, contact_phone: "5547999990043", status: "open")
      message = conversation.messages.create!(tenant: tenant, direction: "outbound", status: "pending", msg_type: "document", body: "Sem binário")
      client = instance_double(Whatsapp::CloudClient)
      allow(Whatsapp::CloudClient).to receive(:new).and_return(client)
      allow(client).to receive(:send_media)

      described_class.perform_now(message.id, tenant_id: tenant.id)

      expect(message.reload.status).to eq("failed")
      expect(message.error_message).to include("Mídia sem arquivo anexado nem link remoto")
      expect(client).not_to have_received(:send_media)
    end
  end
end
