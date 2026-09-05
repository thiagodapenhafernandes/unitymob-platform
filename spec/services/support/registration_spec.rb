require 'rails_helper'
RSpec.describe Support::Registration do
  around do |example|
    old = ENV.to_h.slice('SUPPORT_INSTANCE_ID', 'SUPPORT_INSTANCE_SECRET', 'SUPPORT_CENTRAL_URL')
    ENV['SUPPORT_INSTANCE_ID'] = 'local-test'
    ENV['SUPPORT_INSTANCE_SECRET'] = 'r' * 64
    ENV['SUPPORT_CENTRAL_URL'] = 'https://admin.example.test'
    example.run
  ensure
    %w[SUPPORT_INSTANCE_ID SUPPORT_INSTANCE_SECRET SUPPORT_CENTRAL_URL].each { |key| ENV[key] = old[key] }
  end

  it 'enfileira a conta nova e mantém identidade estável sem ação humana' do
    expect { @tenant = Tenant.create!(name: 'Nova conta', slug: "auto-#{SecureRandom.hex(4)}") }.to have_enqueued_job(Support::RegisterAccountsJob)
    account = described_class.local_account(@tenant)
    expect(account.uid).to eq("local-test:#{@tenant.id}")
    expect(described_class.local_account(@tenant)).to eq(account)
  end

  it 'descobre contas existentes, conserva cadastro local durante falha e recupera na recorrência' do
    tenant = Tenant.create!(name: 'Existente', slug: "auto-#{SecureRandom.hex(4)}")
    allow(Support::Transport).to receive(:post).and_raise(Support::Transport::DeliveryError.new('offline'))
    expect { Support::RegisterAccountsJob.perform_now(tenant.id) }.not_to raise_error
    account = Support::Account.find_by!(local_tenant_id: tenant.id)
    allow(Support::Transport).to receive(:post).and_return({ 'uid' => account.uid })
    Support::RegisterAccountsJob.perform_now(tenant.id)
    expect(Support::Transport).to have_received(:post).with(have_attributes(uid: 'local-test'), '/internal/support/v1/accounts', {tenant_id: tenant.id.to_s, name: tenant.name}).twice
  end
  it 'não falha o cadastro da conta se a fila estiver indisponível' do
    allow(Support::RegisterAccountsJob).to receive(:perform_later).and_raise(SolidQueue::Job::EnqueueError, 'offline')
    expect { Tenant.create!(name: 'Fila indisponível', slug: "auto-#{SecureRandom.hex(4)}") }.to change(Tenant, :count).by(1)
  end

end
