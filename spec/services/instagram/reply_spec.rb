require "rails_helper"

RSpec.describe Instagram::Reply do
  let(:tenant) { Tenant.default }
  let(:broker) { create(:admin_user, tenant:) }
  let(:integration) { create(:user_meta_integration, admin_user: broker) }
  let!(:page) do
    create(:meta_facebook_page, user_meta_integration: integration,
      instagram_id: "555", instagram_enabled: true, active: true)
  end
  let(:lead) do
    create(:lead, tenant:, origin: "Instagram Direct",
      instagram_account_id: "555", instagram_scoped_id: "777")
  end
  let(:graph) { instance_double(Koala::Facebook::API) }

  before do
    allow(Koala::Facebook::API).to receive(:new).with("page-token").and_return(graph)
    lead.instagram_messages.create!(message_id: "mid-1", body: "Olá, tenho interesse",
      occurred_at: 1.hour.ago)
  end

  it "envia a resposta, grava outbound e registra atividade" do
    allow(graph).to receive(:put_connections).and_return({ "message_id" => "mid-out-1" })

    message = described_class.call(lead:, body: "Olá! Vamos conversar?", admin_user: broker)

    expect(graph).to have_received(:put_connections).with("555", "messages",
      hash_including(messaging_type: "RESPONSE"))
    expect(message).to have_attributes(direction: "outbound", body: "Olá! Vamos conversar?",
      message_id: "mid-out-1", sent_by_admin_user: broker)
    expect(lead.activities.where(kind: "instagram_out")).to exist
  end

  it "identifica links próprios enviados manualmente e só registra o imóvel após o envio" do
    property = create(:habitation, tenant: tenant)
    allow_any_instance_of(Tenant).to receive(:public_base_url).and_return("https://catalogo.example")
    allow(graph).to receive(:put_connections).and_return({"message_id" => "mid-property"})
    message = described_class.call(lead: lead, body: "Veja https://catalogo.example/imoveis/#{property.slug}", admin_user: broker)
    url = message.body.split.last
    token = Instagram::PropertyJourney.token_from_url(url)
    expect(Instagram::PropertyJourney.resolve(tenant, token)).to eq(lead)
    expect(lead.activities.where(kind: "instagram_property_event").last.metadata).to include("event" => "sent", "habitation_id" => property.id)
    expect(lead.property_interests).to be_empty
  end

  it "mostra o indicador antes da resposta automática e o encerra depois" do
    expect(graph).to receive(:put_connections).with(page.page_id, "messages", hash_including(sender_action: "typing_on")).ordered
    expect(graph).to receive(:put_connections).with("555", "messages", hash_including(messaging_type: "RESPONSE"))
      .ordered.and_return({ "message_id" => "mid-auto" })
    expect(graph).to receive(:put_connections).with(page.page_id, "messages", hash_including(sender_action: "typing_off")).ordered

    expect(described_class.call(lead:, body: "Seu nome?", admin_user: nil, typing: true).message_id).to eq("mid-auto")
  end

  it "envia a resposta automática mesmo quando a Meta recusa o indicador" do
    api_error = Koala::Facebook::APIError.new(400, { error: { code: 100 } }.to_json)
    expect(graph).to receive(:put_connections).with(page.page_id, "messages", hash_including(sender_action: "typing_on"))
      .ordered.and_raise(api_error)
    expect(graph).to receive(:put_connections).with("555", "messages", hash_including(messaging_type: "RESPONSE"))
      .ordered.and_return({ "message_id" => "mid-fallback" })

    expect(described_class.call(lead:, body: "Seu nome?", admin_user: nil, typing: true).message_id).to eq("mid-fallback")
  end

  it "envia o resumo e o link quando a Meta recusa o cartão" do
    card = { title: "Apartamento", image_url: "https://catalogo.example/foto.jpg",
      buttons: [{ type: "web_url", title: "Ver imóvel", url: "https://catalogo.example/imoveis/123" }] }
    body = "Apartamento\nhttps://catalogo.example/imoveis/123"
    error = Koala::Facebook::APIError.new(400, { error: { code: 100 } }.to_json)
    expect(graph).to receive(:put_connections).with("555", "messages", hash_including(message: satisfy { |json|
      JSON.parse(json).dig("attachment", "payload", "elements") == [card.deep_stringify_keys]
    })).ordered.and_raise(error)
    expect(graph).to receive(:put_connections).with("555", "messages", hash_including(message: { text: body }.to_json))
      .ordered.and_return({ "message_id" => "mid-text" })

    expect(described_class.call(lead:, body:, admin_user: nil, cards: [card])).to have_attributes(
      message_id: "mid-text", body: body
    )
  end

  it "barra fora da janela de 24h" do
    lead.instagram_messages.update_all(occurred_at: 25.hours.ago)
    allow(graph).to receive(:put_connections)

    expect { described_class.call(lead:, body: "Oi", admin_user: broker) }
      .to raise_error(described_class::Error, /24h/)
    expect(graph).not_to have_received(:put_connections)
    expect(described_class.window_open?(lead)).to be(false)
  end

  it "barra sem página vinculada na conta" do
    page.update!(instagram_enabled: false)
    allow(graph).to receive(:put_connections)

    expect { described_class.call(lead:, body: "Oi", admin_user: broker) }
      .to raise_error(described_class::Error, /desconectada/)
    expect(graph).not_to have_received(:put_connections)
  end

  it "valida texto em branco e limite de caracteres" do
    allow(graph).to receive(:put_connections)

    expect { described_class.call(lead:, body: "  ", admin_user: broker) }
      .to raise_error(described_class::Error, /Digite a mensagem/)
    expect { described_class.call(lead:, body: "x" * 1001, admin_user: broker) }
      .to raise_error(described_class::Error, /1000/)
    expect(graph).not_to have_received(:put_connections)
  end

  it "traduz erro de permissão da Meta sem vazar o token" do
    api_error = Koala::Facebook::APIError.new(403, { error: { code: 230, message: "Permissions error" } }.to_json)
    allow(graph).to receive(:put_connections).and_raise(api_error)

    expect { described_class.call(lead:, body: "Oi", admin_user: broker) }
      .to raise_error(described_class::Error, /permissão/)
  end
  it 'sinaliza digitação antes do trabalho e encerra mesmo quando a geração falha' do
    allow(described_class).to receive(:sleep)
    expect(graph).to receive(:put_connections).with(page.page_id, 'messages', recipient: {id: '777'}.to_json, sender_action: 'typing_on').ordered
    expect(graph).to receive(:put_connections).with(page.page_id, 'messages', recipient: {id: '777'}.to_json, sender_action: 'typing_off').ordered
    expect { described_class.with_typing(lead, {'typing_enabled' => true, 'typing_seconds' => 2}) { raise 'generation failed' } }.to raise_error('generation failed')
    expect(described_class).to have_received(:sleep).with(2)
  end

  it 'respeita a desativação de digitação e bloqueia envio automático após atribuição' do
    expect(graph).not_to receive(:put_connections)
    expect(described_class.with_typing(lead, {'typing_enabled' => false}) { 'ok' }).to eq('ok')
    lead.update_columns(admin_user_id: broker.id)
    expect { described_class.call(lead: lead, body: 'Automática', admin_user: nil) }.to raise_error(described_class::Error, /atribuído/)
  end

end
