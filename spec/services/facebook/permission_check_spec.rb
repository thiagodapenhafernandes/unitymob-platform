require "rails_helper"
RSpec.describe Facebook::PermissionCheck do
  let(:integration) { build_stubbed(:user_meta_integration, token_expires_at: 1.day.from_now) }
  let(:graph) { double("Graph") }
  before { allow(Koala::Facebook::API).to receive(:new).with(integration.access_token).and_return(graph) }

  it "distingue concessão, recusa e ausência e aceita ads_read para leitura" do
    allow(graph).to receive(:get_connections).with("me", "permissions").and_return([
      {"permission" => "instagram_manage_messages", "status" => "declined"},
      {"permission" => "pages_show_list", "status" => "granted"},
      {"permission" => "ads_read", "status" => "granted"}
    ])
    rows = described_class.call(integration)[:permissions].index_by { |row| row[:key] }
    expect(rows["instagram_manage_messages"][:status]).to eq("declined")
    expect(rows["instagram_basic"][:status]).to eq("missing")
    expect(rows["pages_show_list"][:status]).to eq("granted")
    expect(rows["ads_management"][:status]).to eq("granted")
  end

  it "não confunde indisponibilidade com permissão negada" do
    allow(graph).to receive(:get_connections).and_raise(Timeout::Error)
    expect(described_class.call(integration)).to have_key(:error)
    expect(described_class.call(integration)).not_to have_key(:permissions)
  end

  it "orienta renovar conexão expirada sem consultar a API" do
    integration.token_expires_at = 1.day.ago
    expect(graph).not_to receive(:get_connections)
    expect(described_class.call(integration)[:error]).to include("expirada")
  end
end
