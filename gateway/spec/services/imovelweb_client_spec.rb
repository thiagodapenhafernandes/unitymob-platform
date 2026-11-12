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
    contact = stub_request(:put, "#{base}/v1/configuracao/callbacks/CONTACTO").to_return(status: 204)
    message = stub_request(:put, "#{base}/v1/configuracao/callbacks/CONTACTO_MENSAJE").to_return(status: 204)
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

  it 'rejects invalid environments and non-official origins' do
    expect { described_class.new(environment: 'development') }.to raise_error(described_class::Error)
    ENV['IMOVELWEB_SANDBOX_API_URL'] = 'https://evil.example.com'
    expect { client }.to raise_error(described_class::Error)
  end
end
