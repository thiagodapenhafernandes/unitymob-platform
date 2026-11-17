require 'rails_helper'

RSpec.describe ImovelwebListingReconcileJob, type: :job do
  it 'prepares only authorized, active production connections' do
    tenant = create(:admin_user, :admin).tenant
    attrs = {tenant: tenant, environment: 'production', enabled: true, authorized_at: Time.current}
    active = ImovelwebConnection.create!(attrs.merge(client_code: SecureRandom.uuid))
    ImovelwebConnection.create!(attrs.merge(client_code: SecureRandom.uuid, enabled: false))
    ImovelwebConnection.create!(attrs.merge(client_code: SecureRandom.uuid, environment: 'sandbox'))
    ImovelwebConnection.create!(attrs.merge(client_code: SecureRandom.uuid, authorized_at: nil))
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('IMOVELWEB_RECEIVING_ENABLED').and_return('true')
    expect { described_class.perform_now }.to have_enqueued_job(ImovelwebListingSyncJob).with(active.id).exactly(:once)
  end
end
