require 'rails_helper'

RSpec.describe ImovelwebListingSyncJob, type: :job do
  let(:connection) { ImovelwebConnection.create!(tenant: create(:admin_user, :admin).tenant, environment: 'production', client_code: "um-#{SecureRandom.uuid}", enabled: true, authorized_at: Time.current) }
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('IMOVELWEB_RECEIVING_ENABLED').and_return('true')
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
  end

  it 'continues one page per job and records completion only after the final page' do
    allow(Imovelweb::GatewayClient).to receive(:associate_listings!).with(connection, page: 0).and_return(1)
    expect { described_class.perform_now(connection.id) }.to have_enqueued_job(described_class).with(connection.id, 1)
    expect(connection.reload.listings_synced_at).to be_nil
    allow(Imovelweb::GatewayClient).to receive(:associate_listings!).with(connection, page: 1).and_return(nil)
    described_class.perform_now(connection.id, 1)
    expect(connection.reload.listings_synced_at).to be_present
    expect(connection.listing_sync_error).to be_nil
    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(connection, :connection_status, anything)
  end

  it 'retries safely and exposes a sanitized error without disabling existing lead reception' do
    allow(Imovelweb::GatewayClient).to receive(:associate_listings!).and_raise(Imovelweb::GatewayClient::Error, 'private error')
    expect { described_class.perform_now(connection.id) }.to have_enqueued_job(described_class)
    expect(connection.reload.listing_sync_error).to include('Tentaremos novamente')
    expect(connection.listing_sync_error).not_to include('private error')
    expect(connection.receiving?).to be(true)
  end

  it 'does not touch sandbox or disabled connections' do
    allow(Imovelweb::GatewayClient).to receive(:associate_listings!)
    connection.update!(enabled: false)
    described_class.perform_now(connection.id)
    connection.update_columns(enabled: true, environment: 'sandbox')
    described_class.perform_now(connection.id)
    expect(Imovelweb::GatewayClient).not_to have_received(:associate_listings!)
  end
end
