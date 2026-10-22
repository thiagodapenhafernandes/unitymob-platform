require 'rails_helper'
RSpec.describe Meta::ConnectionCompletion do
  let(:integration) { create(:user_meta_integration, facebook_user_id: '123', access_token: 'old', selected_page_ids: ['page-1']) }
  let(:identity) { {'facebook_user_id' => '123', 'access_token' => 'new', 'granted_permissions' => %w[ads_management instagram_basic]} }
  before do
    allow(Facebook::MetaService).to receive(:exchange_access_token).and_return(nil)
    allow(Facebook::PermissionCheck).to receive(:statuses).and_return('ads_management' => 'granted', 'instagram_basic' => 'granted')
    allow(MetaSyncJob).to receive(:perform_later).and_return(true)
    allow(Facebook::PermissionCheck).to receive(:token_access).and_return(
      { 'is_valid' => true, 'app_id' => ENV['FACEBOOK_APP_ID'], 'user_id' => '123',
        'scopes' => %w[ads_management instagram_basic], 'granular_scopes' => [
          { 'scope' => 'instagram_basic', 'target_ids' => ['ig-1'] }
        ] })
  end
  it 'preserves selected assets and existing Instagram permissions' do
    described_class.call(integration: integration, identity: identity, preserve_permissions: true)
    expect(integration.reload.access_token).to eq('new')
    expect(integration.selected_page_ids).to eq(['page-1'])
  end
  it 'refuses a token that drops Instagram without modifying the integration' do
    identity['granted_permissions'] = ['ads_management']
    expect { described_class.call(integration: integration, identity: identity, preserve_permissions: true) }.to raise_error(described_class::PermissionLoss)
    expect(integration.reload.access_token).to eq('old')
    expect(MetaSyncJob).not_to have_received(:perform_later)
  end
  it 'fails closed when current permissions cannot be established' do
    allow(Facebook::PermissionCheck).to receive(:statuses).and_return({})
    expect { described_class.call(integration: integration, identity: identity, preserve_permissions: true) }.to raise_error(described_class::PermissionLoss)
  end
  it 'refuses a different Facebook identity' do
    identity['facebook_user_id'] = '456'
    expect { described_class.call(integration: integration, identity: identity, preserve_permissions: true) }.to raise_error(described_class::PermissionLoss)
    expect(integration.reload.access_token).to eq('old')
  end
  it 'rolls back token replacement if job scheduling fails' do
    integration
    allow(MetaSyncJob).to receive(:perform_later).and_raise('queue unavailable')
    expect { described_class.call(integration: integration, identity: identity, preserve_permissions: true) }.to raise_error('queue unavailable')
    expect(integration.reload.access_token).to eq('old')
  end

  it 'refuses loss of an authorized asset even when permission names are unchanged' do
    original = Facebook::PermissionCheck.token_access('old')
    replacement = original.deep_dup
    replacement['granular_scopes'].first['target_ids'] = ['another-profile']
    allow(Facebook::PermissionCheck).to receive(:token_access).with('new').and_return(replacement)
    expect { described_class.call(integration: integration, identity: identity, preserve_permissions: true) }.to raise_error(described_class::PermissionLoss)
    expect(integration.reload.access_token).to eq('old')
    expect(MetaSyncJob).not_to have_received(:perform_later)
  end

  it 'checks the exchanged token and rejects a different app or unverified assets' do
    allow(Facebook::MetaService).to receive(:exchange_access_token).and_return('access_token' => 'long-token')
    allow(Facebook::PermissionCheck).to receive(:token_access).with('long-token').and_return(
      { 'is_valid' => true, 'app_id' => 'wrong-app', 'user_id' => '123', 'scopes' => identity['granted_permissions'], 'granular_scopes' => [] })
    expect { described_class.call(integration: integration, identity: identity, preserve_permissions: true) }.to raise_error(described_class::PermissionLoss)
    expect(integration.reload.access_token).to eq('old')
  end

  it 'preserves a concurrent reconnection instead of overwriting it' do
    record = integration
    allow(Facebook::MetaService).to receive(:exchange_access_token) do
      record.class.find(record.id).update!(access_token: 'concurrently-updated')
      nil
    end
    expect { described_class.call(integration: record, identity: identity, preserve_permissions: true) }.to raise_error(described_class::PermissionLoss)
    expect(record.reload.access_token).to eq('concurrently-updated')
    expect(MetaSyncJob).not_to have_received(:perform_later)
  end

  it 'does not add central permission checks to the legacy callback' do
    expect(Facebook::PermissionCheck).not_to receive(:token_access)
    described_class.call(integration: integration, identity: identity)
    expect(integration.reload.access_token).to eq('new')
  end
end
