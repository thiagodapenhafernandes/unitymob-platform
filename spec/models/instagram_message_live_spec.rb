require 'rails_helper'
RSpec.describe InstagramMessage do
  let(:lead) { create(:lead) }
  it 'notifica mensagens recebidas e enviadas sem transmitir conteúdo ou contatos' do
    allow(ActionCable.server).to receive(:broadcast)
    %w[inbound outbound].each do |direction|
      lead.instagram_messages.create!(message_id: SecureRandom.uuid, body: 'Privado', direction: direction, occurred_at: Time.current)
    end
    expect(ActionCable.server).to have_received(:broadcast).with(LeadConversationChannel.stream_name(lead), {refresh: true}).twice
  end
  it 'uma falha do Redis não perde a mensagem já recebida' do
    allow(ActionCable.server).to receive(:broadcast).and_raise(IOError)
    message = lead.instagram_messages.create!(message_id: SecureRandom.uuid, body: 'Privado', occurred_at: Time.current)
    expect(message.reload.body).to eq('Privado')
  end
  it 'rejeita URLs executáveis e payloads malformados, preservando títulos como dados' do
    context = described_class.received_context("reply_to" => "invalid", "attachments" => [nil,
      {"type" => "ig_post", "payload" => {"url" => "javascript:alert(1)", "title" => "Casa"}},
      {"type" => "image", "payload" => {"url" => "https://user:pass@example.com/image"}}])
    message = described_class.new(body: "", context: context)
    expect(message.media_urls).to be_empty
    expect(message.context_description).to include("Casa")
    expect(message.automation_input?).to be(false)
  end

  it 'preserva anúncios sem texto e mensagens comuns, sem interpretar reações como pedido' do
    message = described_class.new(body: "", context: {"referral" => {"ad_id" => "123"}})
    expect(message.automation_input?).to be(true)
    message.assign_attributes(body: "Oi", context: {})
    expect(message.automation_input?).to be(true)
    message.body = "😍"
    expect(message.automation_input?).to be(false)
  end

end
