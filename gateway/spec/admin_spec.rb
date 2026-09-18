require 'spec_helper'

RSpec.describe 'Admin panel' do
  def app = Gateway::App

  def csrf_token
    last_response.body[/name="authenticity_token" value="([^"]+)"/, 1]
  end

  before do
    ENV['GATEWAY_ADMIN_SECRET'] = 'a' * 40
    ENV['SESSION_SECRET'] = 'b' * 64
    ENV['GATEWAY_ADMIN_EMAIL'] = 'contato@unitymob.com.br'
    ENV['GATEWAY_ADMIN_PASSWORD_DIGEST'] = Gateway::AdminAuth.hash_password('correct-horse')
    ENV['DISCOVERY_MAIL_FROM'] = 'gateway@unitymob.com.br'
    allow(Gateway::AdminAuth).to receive(:send_code) { |code| @code = code }
  end

  after do
    %w[GATEWAY_ADMIN_SECRET SESSION_SECRET GATEWAY_ADMIN_EMAIL GATEWAY_ADMIN_PASSWORD_DIGEST DISCOVERY_MAIL_FROM].each { |key| ENV.delete(key) }
  end

  def login(email: 'contato@unitymob.com.br', password: 'correct-horse')
    get '/admin/login'
    token = csrf_token
    post '/admin/login', email: email, password: password, authenticity_token: token
  end

  it 'redirects unauthenticated visitors to login' do
    get '/admin'
    expect(last_response.status).to eq(302)
    expect(last_response.location).to include('/admin/login')
  end

  it 'requires the correct password before sending a code' do
    login(password: 'wrong')
    expect(last_response.body).to include('Credenciais inválidas')
    expect(@code).to be_nil
  end

  it 'completes login with the emailed code and reaches the dashboard' do
    route = WebhookRoute.create!(provider: 'whatsapp', client_key: 'default', tenant_name: 'Salute', phone_number_id: '123', waba_id: '456', target_url: 'https://saluteimoveis.com.br/webhooks/whatsapp', forwarding_secret: 'x' * 20)

    login
    expect(last_response.status).to eq(302)
    expect(last_response.location).to include('/admin/login/verify')
    expect(@code).to match(/\A\d{6}\z/)

    get last_response.location
    token = csrf_token
    post '/admin/login/verify', code: @code, authenticity_token: token
    expect(last_response.status).to eq(302)
    expect(last_response.location).to include('/admin')

    get '/admin'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('Salute')
    expect(last_response.body).to include(route.target_url)
    expect(last_response.body).to include("/admin/routes/#{route.id}")
    expect(last_response.body).to include('Nova conexão')
    expect(last_response.body).to include('Espelho dev')
  end

  it 'shows events for a selected connection' do
    route = WebhookRoute.create!(provider: 'meta', client_key: 'conexao', tenant_name: 'Conexão', page_id: 'page-1', form_id: 'form-1', target_url: 'https://app.conexaobc.com/webhooks/meta', forwarding_secret: 'x' * 20)
    WebhookEvent.create!(provider: 'meta', webhook_route: route, external_id: 'lead-1', event_type: 'leadgen', page_id: 'page-1', form_id: 'form-1', payload: {}, status: 'forwarded', attempts: 1, received_at: Time.now.utc, forwarded_at: Time.now.utc)
    WebhookEvent.create!(provider: 'meta', webhook_route: route, external_id: 'lead-2', event_type: 'leadgen', page_id: 'page-1', form_id: 'form-1', payload: {}, status: 'failed', attempts: 2, last_error: 'HTTP 500', received_at: Time.now.utc - 60)

    login
    get '/admin/login/verify'
    post '/admin/login/verify', code: @code, authenticity_token: csrf_token

    get "/admin/routes/#{route.id}"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('Conexão')
    expect(last_response.body).to include('lead-1')
    expect(last_response.body).to include('forwarded')
    expect(last_response.body).to include('HTTP 500')

    get "/admin/routes/#{route.id}", status: 'failed'
    expect(last_response.body).to include('lead-2')
    expect(last_response.body).not_to include('lead-1')
  end

  it 'creates a manual route from the admin panel' do
    login
    get '/admin/login/verify'
    post '/admin/login/verify', code: @code, authenticity_token: csrf_token
    get '/admin'

    post '/admin/routes',
      route_provider: 'meta',
      client_key: 'dev',
      tenant_name: 'Dev Unitymob',
      page_id: 'page-dev',
      form_id: 'form-dev',
      target_url: 'https://dev.unitymob.com.br/webhooks/meta',
      forwarding_secret: 'secret-dev',
      active: 'true',
      authenticity_token: csrf_token

    route = WebhookRoute.find_by!(provider: 'meta', page_id: 'page-dev', form_id: 'form-dev')
    expect(last_response.status).to eq(302)
    expect(last_response.location).to include("/admin/routes/#{route.id}")
    expect(route).to have_attributes(client_key: 'dev', target_url: 'https://dev.unitymob.com.br/webhooks/meta', active: true)
  end

  it 'updates the dev mirror from the admin panel' do
    login
    get '/admin/login/verify'
    post '/admin/login/verify', code: @code, authenticity_token: csrf_token
    get '/admin'

    post '/admin/dev_mirror',
      provider: 'all',
      target_url: 'https://dev.unitymob.com.br',
      forwarding_secret: 'secret-dev',
      active: 'true',
      authenticity_token: csrf_token

    mirror = WebhookMirror.find_by!(name: 'Dev Unitymob')
    expect(last_response.status).to eq(302)
    expect(mirror).to have_attributes(provider: 'all', active: true, target_url: 'https://dev.unitymob.com.br')
  end

  it 'rejects a wrong code without consuming it, then accepts the right one' do
    login
    get '/admin/login/verify'
    token = csrf_token

    post '/admin/login/verify', code: '000000', authenticity_token: token
    expect(last_response.body).to include('Código inválido')

    post '/admin/login/verify', code: @code, authenticity_token: token
    expect(last_response.status).to eq(302)
  end

  it 'rejects requests without a valid csrf token' do
    get '/admin/login'
    post '/admin/login', email: 'contato@unitymob.com.br', password: 'correct-horse', authenticity_token: 'forged'
    expect(last_response.status).to eq(403)
  end
end
