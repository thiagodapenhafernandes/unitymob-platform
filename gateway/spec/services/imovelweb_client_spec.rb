require 'spec_helper'

RSpec.describe Gateway::ImovelwebClient do
  let(:base) { 'https://api-br.sandbox.open.navent.com' }
  let(:client) { described_class.new(environment: 'sandbox') }
  before do
    @variables = %w[IMOVELWEB_SANDBOX_API_URL IMOVELWEB_SANDBOX_CLIENT_ID IMOVELWEB_SANDBOX_CLIENT_SECRET]
    @previous = ENV.to_h.slice(*@variables)
    ENV['IMOVELWEB_SANDBOX_API_URL'] = base
    ENV['IMOVELWEB_SANDBOX_CLIENT_ID'] = 'unitymob'
    ENV['IMOVELWEB_SANDBOX_CLIENT_SECRET'] = 'secret'
    stub_request(:post, "#{base}/v1/application/login").with(query: {grant_type: 'client_credentials', client_id: 'unitymob', client_secret: 'secret'})
      .to_return(body: {access_token: 'access-token', expires_in: 3600}.to_json)
  end
  after { @variables.each { |key| @previous.key?(key) ? ENV[key] = @previous[key] : ENV.delete(key) } }

  it 'uses the Brazilian sandbox contract to configure EN callbacks with a dedicated header and subscribes to both lead events' do
    setup = stub_request(:put, "#{base}/v1/configuracao/callbacks").with(headers: {'Authorization' => 'Bearer access-token'},
      body: {url: 'https://webhooks.example.com/webhooks/imovelweb/sandbox', authorizationHeaderKey: 'Authorization', authorizationHeaderValue: "Bearer #{'t' * 32}", lenguajeCallbackBody: 'EN'}.to_json).to_return(status: 204)
    contact = stub_request(:put, "#{base}/v1/configuracao/callbacks/CONTACTO?evento=CONTACTO").to_return(status: 204)
    message = stub_request(:put, "#{base}/v1/configuracao/callbacks/CONTACTO_MENSAJE?evento=CONTACTO_MENSAJE").to_return(status: 204)
    client.configure_callbacks(url: 'https://webhooks.example.com/webhooks/imovelweb/sandbox', token: 't' * 32)
    [setup, contact, message].each { |request| expect(request).to have_been_requested.once }
  end

  it 'associates only the selected readonly listing, escaping path segments' do
    association = stub_request(:put, "#{base}/v1/imobiliarias/client/anuncios/AP%2F1/asociar/123").to_return(status: 204)
    client.associate_listing(client_code: 'client', reference: 'AP/1', external_id: '123')
    expect(association).to have_been_requested.once
  end

  it 'refreshes a revoked token once and sanitizes errors' do
    login = stub_request(:post, "#{base}/v1/application/login").with(query: hash_including('grant_type' => 'client_credentials')).to_return(body: {access_token: 'new-token', expires_in: 3600}.to_json)
    endpoint = stub_request(:get, "#{base}/v1/configuracao/callbacks").to_return(status: 401, body: 'private contact details')
    expect { client.callbacks }.to raise_error(described_class::Error, 'Imovelweb authentication failed')
    expect(login).to have_been_requested.twice
    expect(endpoint).to have_been_requested.twice
  end

  it 'accepts the official Brazilian production API origin' do
    allow(ENV).to receive(:fetch).with('IMOVELWEB_PRODUCTION_API_URL').and_return('https://api-br-open.navent.com')
    expect { described_class.new(environment: 'production') }.not_to raise_error
  end

  it 'rejects invalid environments and non-official origins' do
    expect { described_class.new(environment: 'development') }.to raise_error(described_class::Error)
    ENV['IMOVELWEB_SANDBOX_API_URL'] = 'https://evil.example.com'
    expect { client }.to raise_error(described_class::Error)
  end
end

RSpec.describe 'Imovelweb advertiser consent' do
  let(:base) { 'https://api-br.example.open.navent.com' }
  let(:client) { Gateway::ImovelwebClient.new(environment: 'production') }
  before do
    @keys = %w[IMOVELWEB_PRODUCTION_API_URL IMOVELWEB_PRODUCTION_CLIENT_ID IMOVELWEB_PRODUCTION_CLIENT_SECRET IMOVELWEB_PRODUCTION_INTEGRATOR_ID]
    @previous = ENV.to_h.slice(*@keys)
    ENV['IMOVELWEB_PRODUCTION_API_URL'] = base
    ENV['IMOVELWEB_PRODUCTION_CLIENT_ID'] = 'unitymob'
    ENV['IMOVELWEB_PRODUCTION_CLIENT_SECRET'] = 'secret'
    ENV['IMOVELWEB_PRODUCTION_INTEGRATOR_ID'] = 'official-id'
    stub_request(:post, "#{base}/v1/application/login").with(query: hash_including('grant_type' => 'client_credentials')).to_return(body: {access_token: 'token', expires_in: 3600}.to_json)
  end
  after { @keys.each { |key| @previous.key?(key) ? ENV[key] = @previous[key] : ENV.delete(key) } }

  it 'builds Login with the unique customer code and configured integrator identifier' do
    expect(client.authorization_script(client_code: 'um-uuid')).to eq('https://loginbr-open.navent.com/official-id/um-uuid.js')
    ENV.delete('IMOVELWEB_PRODUCTION_INTEGRATOR_ID')
    expect { client.authorization_script(client_code: 'um-uuid') }.to raise_error(Gateway::ImovelwebClient::Error)
  end

  it 'finds the exact code across pages, returning only its advertiser identity' do
    stub_request(:get, "#{base}/v1/imobiliarias?pageable.page=0&pageable.size=100").to_return(body: {content: [{codigoInmobiliaria: 'another', idNavplat: 111}], total: 101}.to_json)
    stub_request(:get, "#{base}/v1/imobiliarias?pageable.page=1&pageable.size=100").to_return(body: {content: [{codigoInmobiliaria: 'um-uuid', idNavplat: 47294717, nombre: 'private'}], total: 101}.to_json)
    expect(client.authorized_advertiser(client_code: 'um-uuid')).to eq(client_code: 'um-uuid', advertiser_code: '47294717')
  end

  it 'does not accept a numeric advertiser ID as consent to a new client code' do
    stub_request(:get, "#{base}/v1/imobiliarias?pageable.page=0&pageable.size=100").to_return(body: {content: [{codigoInmobiliaria: 'existing', idNavplat: 47294717}], total: 1}.to_json)
    expect(client.authorized_advertiser(client_code: '47294717')).to be_nil
  end

  it 'rejects a blocked advertiser even when the customer code matches' do
    stub_request(:get, "#{base}/v1/imobiliarias?pageable.page=0&pageable.size=100").to_return(body: {content: [{codigoInmobiliaria: 'um-uuid', idNavplat: 47294717, bloqueada: true}], total: 1}.to_json)
    expect { client.authorized_advertiser(client_code: 'um-uuid') }.to raise_error(Gateway::ImovelwebClient::Error, /blocked/)
  end

  it 'fails closed for malformed and ambiguous provider identities' do
    endpoint = stub_request(:get, "#{base}/v1/imobiliarias?pageable.page=0&pageable.size=100").to_return(body: {content: [{codigoInmobiliaria: 'um-uuid'}]}.to_json)
    expect { client.authorized_advertiser(client_code: 'um-uuid') }.to raise_error(Gateway::ImovelwebClient::Error)
    endpoint.to_return(body: {content: [{codigoInmobiliaria: 'um-uuid', idNavplat: 1}, {codigoInmobiliaria: 'um-uuid', idNavplat: 2}]}.to_json)
    expect { client.authorized_advertiser(client_code: 'um-uuid') }.to raise_error(Gateway::ImovelwebClient::Error)
  end
end

RSpec.describe 'Imovelweb readonly listing preparation' do
  let(:client) { Gateway::ImovelwebClient.new(environment: 'production') }
  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('IMOVELWEB_PRODUCTION_API_URL').and_return('https://api-br.example.open.navent.com')
  end

  it 'associates missing references only and preserves previously linked listings and publication' do
    allow(client).to receive(:request).with(:get, '/v1/imobiliarias/um-uuid/anuncios/online/resumo?pageable.page=0&pageable.size=5').and_return('number' => 0, 'total' => 2, 'content' => [{'idAvisoNavplat' => 123, 'codigoAviso' => 'AP-1'}, {'idAvisoNavplat' => 456, 'codigoAviso' => nil}])
    expect(client).to receive(:associate_listing).with(client_code: 'um-uuid', reference: 'iw-456', external_id: '456')
    expect(client).not_to receive(:associate_listing).with(hash_including(external_id: '123'))
    expect(client.associate_online_listings(client_code: 'um-uuid', page: 0)).to eq(associated: 1, next_page: nil)
  end

  it 'handles an advertiser with no online listings and continues a bounded batch' do
    allow(client).to receive(:request).and_return(nil)
    expect(client.associate_online_listings(client_code: 'um-uuid', page: 0)).to eq(associated: 0, next_page: nil)
    allow(client).to receive(:request).and_return('number' => 0, 'total' => 10, 'content' => (1..5).map { |id| {'idAvisoNavplat' => id, 'codigoAviso' => "kept-#{id}"} })
    expect(client.associate_online_listings(client_code: 'um-uuid', page: 0)).to eq(associated: 0, next_page: 1)
  end

  it 'rejects invalid provider data rather than editing or publishing a listing' do
    allow(client).to receive(:request).and_return('number' => 0, 'total' => 1, 'content' => [{'idAvisoNavplat' => '../private'}])
    expect(client).not_to receive(:associate_listing)
    expect { client.associate_online_listings(client_code: 'um-uuid', page: 0) }.to raise_error(Gateway::ImovelwebClient::Error)
  end
end
