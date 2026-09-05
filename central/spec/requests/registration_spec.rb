require 'rails_helper'
RSpec.describe 'Registro automático de contas', type: :request do
  around do |example|
    previous = ENV['SUPPORT_TRUSTED_INSTANCES']
    ENV['SUPPORT_TRUSTED_INSTANCES'] = { 'server-a' => { secret: 'a' * 64, endpoint: 'https://crm-a.example.test' }, 'server-b' => { secret: 'b' * 64, endpoint: 'https://crm-b.example.test' } }.to_json
    example.run
  ensure
    ENV['SUPPORT_TRUSTED_INSTANCES'] = previous
  end

  def register(instance = 'server-a', key = 'a' * 64, timestamp = Time.current.to_i.to_s, extra = {})
    body = { tenant_id: '72', name: 'Conexão' }.merge(extra).to_json
    post '/internal/support/v1/accounts', params: body, headers: { 'CONTENT_TYPE' => 'application/json', 'X-Support-Account' => instance, 'X-Support-Timestamp' => timestamp, 'X-Support-Signature' => Support::Transport.signature(key, timestamp, body) }
  end

  it 'cadastra sem operador, repete sem duplicar e ignora endpoint/credencial fornecidos pelo cliente' do
    register('server-a', 'a' * 64, Time.current.to_i.to_s, endpoint: 'http://169.254.169.254', secret: 'malicioso')
    expect(response).to have_http_status(:ok)
    account = Support::Account.find_by!(uid: 'server-a:72')
    expect(account.endpoint).to eq('https://crm-a.example.test')
    expect(account.secret).to eq(Support::Registration.secret('a' * 64, account.uid))
    account.update!(active: false)
    expect { register }.not_to change(Support::Account, :count)
    expect(response).to have_http_status(:ok)
    expect(account.reload).not_to be_active
  end

  it 'separa o mesmo ID de conta em servidores diferentes' do
    register
    register('server-b', 'b' * 64)
    expect(response).to have_http_status(:ok)
    expect(Support::Account.where(uid: %w[server-a:72 server-b:72]).count).to eq(2)
  end

  it 'rejeita servidor desconhecido, assinatura inválida, replay expirado e payload inválido' do
    register('intruso')
    expect(response).to have_http_status(:unauthorized)
    register('server-a', 'errado')
    expect(response).to have_http_status(:unauthorized)
    register('server-a', 'a' * 64, 6.minutes.ago.to_i.to_s)
    expect(response).to have_http_status(:unauthorized)
    register('server-a', 'a' * 64, Time.current.to_i.to_s, tenant_id: '../../other')
    expect(response).to have_http_status(:unprocessable_entity)
    expect(Support::Account.count).to eq(0)
  end
end
