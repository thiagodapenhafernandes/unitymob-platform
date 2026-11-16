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

  it 'seleciona players por tipo, deduplica stories e descarta endereços inseguros' do
    message = described_class.new(context: {"story_url" => "https://example.com/story", "attachments" => [
      {"type" => "story_mention", "url" => "https://example.com/story"},
      {"type" => "image", "url" => "https://example.com/image"},
      {"type" => "ig_reel", "url" => "https://example.com/video"},
      {"type" => "audio", "url" => "https://example.com/audio"},
      {"type" => "file", "url" => "https://example.com/file"},
      {"type" => "image", "url" => "javascript:alert(1)"}
    ]})
    expect(message.media_items.pluck(:kind)).to eq(%w[auto image video audio document])
    expect(message.media_urls.size).to eq(5)
  end

  it 'extrai o código explícito da legenda sem tratar telefone como referência de imóvel' do
    message = described_class.new(body: '47998887777')
    expect(message.property_reference_codes).to be_empty
    message.context = {'attachments' => [{'title' => 'À venda. Cód. 9705'}]}
    expect(message.property_reference_codes).to eq(['9705'])
    message.body = 'Código: 9525'
    expect(message.property_reference_codes).to eq(['9525'])
    message.body = 'Código 9525, meu WhatsApp é (47) 99888-7777'
    expect(message.property_reference_codes).to eq(['9525'])
  end

  it 'explica o anexo temporário sem URL sem inventar conteúdo ou acionar o SDR' do
    context = described_class.received_context('attachments' => [{'type' => 'ephemeral'}])
    message = described_class.new(body: '', context: context)
    expect(message.context_description).to eq('Mídia temporária: conteúdo não disponibilizado pela Meta')
    expect(message.media_items).to be_empty
    expect(message.automation_input?).to be(false)
    message.context = {'attachments' => [{'type' => 'ephemeral', 'url' => 'https://example.com/media'}]}
    expect(message.context_description).to eq('Enviou uma mídia temporária')
    expect(message.media_urls).to eq(['https://example.com/media'])
  end

end
