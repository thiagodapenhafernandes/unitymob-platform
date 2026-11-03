require "rails_helper"

RSpec.describe Imovelweb::GatewayClient do
  let(:tenant) { create(:admin_user, :admin).tenant }
  let(:connection) { ImovelwebConnection.create!(tenant: tenant, client_code: "client") }
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("APP_HOST").and_return("https://crm.example.com")
    allow(described_class).to receive(:forwarding_secret).and_return("s" * 32)
    allow(Meta::WebhookGatewayClient).to receive(:gateway_url).and_return("https://gateway.example.com")
    allow(Meta::WebhookGatewayClient).to receive(:internal_token).and_return("internal")
  end

  it "registers a disabled route without enabling the client" do
    expect(HTTParty).to receive(:post) do |url, options|
      expect(url).to eq("https://gateway.example.com/internal/imovelweb/routes")
      expect(JSON.parse(options.fetch(:body))).to include("client_key" => connection.route_key, "client_code" => "client", "environment" => "sandbox", "active" => false)
      expect(options.fetch(:headers)).to include("Authorization" => "Bearer internal")
      double(success?: true)
    end
    expect(described_class.sync!(connection)).to eq(true)
    expect(connection.reload.enabled).to eq(false)
  end

  it "does not accept registration failure as a connection" do
    allow(HTTParty).to receive(:post).and_return(double(success?: false, code: 409))
    expect { described_class.sync!(connection) }.to raise_error(RuntimeError, /HTTP 409/)
    expect(connection.reload.enabled).to eq(false)
  end
end
