require 'spec_helper'

RSpec.describe 'Discovery email delivery' do
  def app = Gateway::App
  before do
    @previous = ENV.to_h.slice('RESEND_API_KEY', 'DISCOVERY_MAIL_FROM', 'DISCOVERY_SECRET')
    ENV['RESEND_API_KEY'] = 're_test_only'
    ENV['DISCOVERY_MAIL_FROM'] = 'acesso@example.com'
    ENV['DISCOVERY_SECRET'] = 's' * 40
  end
  after do
    %w[RESEND_API_KEY DISCOVERY_MAIL_FROM DISCOVERY_SECRET].each { |key| ENV.delete(key) }
    ENV.update(@previous)
  end
  it 'sends only the code and recipient to the fixed HTTPS API' do
    delivery = stub_request(:post, 'https://api.resend.com/emails').with do |request|
      payload = JSON.parse(request.body)
      request.headers['Authorization'] == 'Bearer re_test_only' &&
        payload['from'] == 'Unitymob <acesso@example.com>' && payload['to'] == ['broker@example.com'] &&
        payload['text'].include?('123456') && payload.keys.sort == %w[from subject text to]
    end.to_return(status: 200, body: {id: 'email-id'}.to_json)
    expect(Gateway::Discovery.send_code('Broker@example.com', '123456')).to eq('email-id')
    expect(delivery).to have_been_requested.once
  end
  [403, 429, 500, 302].each do |status|
    it "fails safely on status #{status} and removes the unusable challenge" do
      stub_request(:post, 'https://api.resend.com/emails').to_return(status: status, body: 'sensitive provider detail', headers: {'Location' => 'https://other.example.com'})
      post '/discovery/v2/challenges', {email: 'broker@example.com'}.to_json, {'CONTENT_TYPE' => 'application/json'}
      expect(last_response.status).to eq(503)
      expect(last_response.body).not_to include('sensitive', 're_test_only', 'broker@example.com')
      expect(DiscoveryChallenge.count).to eq(0)
    end
  end
  it 'rejects a timeout and a success response without an ID' do
    stub_request(:post, 'https://api.resend.com/emails').to_timeout
    expect { Gateway::Discovery.send_code('broker@example.com', '123456') }.to raise_error(Timeout::Error)
    stub_request(:post, 'https://api.resend.com/emails').to_return(status: 200, body: '{}')
    expect { Gateway::Discovery.send_code('broker@example.com', '123456') }.to raise_error(IOError, 'Invalid email delivery response')
  end
end
