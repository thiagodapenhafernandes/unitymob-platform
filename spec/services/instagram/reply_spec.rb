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
end
