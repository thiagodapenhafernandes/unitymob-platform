require "rails_helper"

RSpec.describe Whatsapp::ExternalMessageMarkerJob, type: :job do
  let(:tenant) { Tenant.default }
  let!(:conversation) { tenant.whatsapp_conversations.create!(contact_phone: "5515034218239", contact_name: "Daniela") }

  before { allow(Whatsapp::ThreadBroadcaster).to receive(:message_created) }

  def run(wamid: "wamid.externa", recipient: "15034218239", at: Time.current.iso8601)
    described_class.perform_now(tenant.id, wamid, recipient, nil, at)
  end

  it "registra no historico que houve uma mensagem enviada por fora" do
    run

    marker = conversation.messages.find_by(wa_message_id: "wamid.externa")
    expect(marker).to have_attributes(direction: "outbound", msg_type: "external", body: described_class::LABEL, admin_user_id: nil)
    expect(Whatsapp::ThreadBroadcaster).to have_received(:message_created).with(marker)
  end

  it "nao duplica quando o aviso chega de novo" do
    run
    expect { run }.not_to change(WhatsappMessage, :count)
  end

  it "ignora mensagens que o sistema ja conhece (envio nosso que so gravou o wamid depois)" do
    conversation.messages.create!(direction: "outbound", msg_type: "text", body: "Oi", status: "sent", wa_message_id: "wamid.nosso")

    expect { run(wamid: "wamid.nosso") }.not_to change(WhatsappMessage, :count)
  end

  it "nao cria conversa para um destinatario desconhecido" do
    expect { run(recipient: "5511900000000") }.not_to change(WhatsappConversation, :count)
    expect(WhatsappMessage.where(msg_type: "external")).to be_empty
  end

  it "o processador agenda o marcador so para o primeiro status de mensagem desconhecida" do
    integration = WhatsappBusinessIntegration.current(tenant).tap { |record| record.update!(status: "connected", phone_number_id: "phone-ext", waba_id: "waba-ext", access_token: "token") }
    payload = ->(state) { { "entry" => [{ "changes" => [{ "field" => "messages", "value" => { "metadata" => { "phone_number_id" => integration.phone_number_id },
                           "statuses" => [{ "id" => "wamid.fora", "status" => state, "recipient_id" => "15034218239", "timestamp" => Time.current.to_i.to_s }] } }] }] } }

    expect { Whatsapp::InboundProcessor.call(payload.call("sent")) }.to have_enqueued_job(described_class)
    expect { Whatsapp::InboundProcessor.call(payload.call("delivered")) }.not_to have_enqueued_job(described_class)
  end
end
