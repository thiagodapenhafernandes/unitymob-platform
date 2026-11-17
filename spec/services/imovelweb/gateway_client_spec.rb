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

RSpec.describe 'Imovelweb self-service API boundary' do
  let(:connection) { ImovelwebConnection.create!(tenant: create(:admin_user, :admin).tenant, environment: 'production', client_code: "um-#{SecureRandom.uuid}") }
  before do
    allow(Meta::WebhookGatewayClient).to receive(:gateway_url).and_return('https://gateway.example.com')
    allow(Meta::WebhookGatewayClient).to receive(:internal_token).and_return('internal')
  end

  it 'accepts only official Login script URLs for the current connection' do
    url = "https://loginbr-open.navent.com/official/#{connection.client_code}.js"
    allow(HTTParty).to receive(:post).and_return(double(success?: true, body: {script_url: url}.to_json))
    expect(Imovelweb::GatewayClient.authorization_script(connection)).to eq(url)
    ['https://evil.example/script.js', "#{url}?redirect=evil", 'https://loginbr-open.navent.com/official/another.js'].each do |bad|
      allow(HTTParty).to receive(:post).and_return(double(success?: true, body: {script_url: bad}.to_json))
      expect { Imovelweb::GatewayClient.authorization_script(connection) }.to raise_error(Imovelweb::GatewayClient::Error)
    end
  end

  it 'requires explicit confirmation with a valid advertiser identity' do
    allow(HTTParty).to receive(:post).and_return(double(success?: true, body: {confirmed: true, advertiser_code: '47294717'}.to_json))
    expect(Imovelweb::GatewayClient.verify!(connection)).to eq('47294717')
    [nil, {confirmed: 'true'}, {confirmed: true}, {confirmed: true, advertiser_code: 'wrong'}].each do |body|
      allow(HTTParty).to receive(:post).and_return(double(success?: true, body: body.to_json))
      expect { Imovelweb::GatewayClient.verify!(connection) }.to raise_error(Imovelweb::GatewayClient::Error)
    end
  end
end

RSpec.describe 'Imovelweb listing batch API boundary' do
  let(:connection) { ImovelwebConnection.create!(tenant: create(:admin_user, :admin).tenant, environment: 'production', client_code: "um-#{SecureRandom.uuid}") }
  before do
    allow(Meta::WebhookGatewayClient).to receive(:gateway_url).and_return('https://gateway.example.com')
    allow(Meta::WebhookGatewayClient).to receive(:internal_token).and_return('internal')
  end
  it 'scopes the batch to the connection identity and checks the returned cursor' do
    expect(HTTParty).to receive(:post).with('https://gateway.example.com/internal/imovelweb/listings', hash_including(timeout: 60, body: {client_code: connection.client_code, environment: 'production', client_key: connection.route_key, page: 0}.to_json)).and_return(double(success?: true, body: {next_page: 1}.to_json))
    expect(Imovelweb::GatewayClient.associate_listings!(connection, page: 0)).to eq(1)
    allow(HTTParty).to receive(:post).and_return(double(success?: true, body: {next_page: -1}.to_json))
    expect { Imovelweb::GatewayClient.associate_listings!(connection, page: 1) }.to raise_error(Imovelweb::GatewayClient::Error)
  end
end
