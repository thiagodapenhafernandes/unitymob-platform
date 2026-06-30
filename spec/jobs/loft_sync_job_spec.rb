require "rails_helper"

RSpec.describe LoftSyncJob, type: :job do
  it "oculta imóveis ausentes da API apenas no tenant do job" do
    current_tenant = Tenant.create!(name: "Tenant loft job #{SecureRandom.hex(3)}", slug: "tenant-loft-job-#{SecureRandom.hex(3)}")
    other_tenant = Tenant.create!(name: "Outro loft job #{SecureRandom.hex(3)}", slug: "outro-loft-job-#{SecureRandom.hex(3)}")
    current_habitation = create(:habitation, tenant: current_tenant, codigo: "12345", exibir_no_site_flag: true, exibir_no_site_salute_flag: true, last_sync_status: "success")
    other_habitation = create(:habitation, tenant: other_tenant, codigo: "12345", exibir_no_site_flag: true, exibir_no_site_salute_flag: true, last_sync_status: "success")
    job = described_class.new
    job.instance_variable_set(:@tenant, current_tenant)

    hidden = job.send(:hide_missing_from_vista_api!, [])

    expect(hidden).to eq(1)
    expect(current_habitation.reload).to have_attributes(exibir_no_site_flag: false, exibir_no_site_salute_flag: false, last_sync_status: "missing_from_vista_api")
    expect(other_habitation.reload).to have_attributes(exibir_no_site_flag: true, exibir_no_site_salute_flag: true, last_sync_status: "success")
  end
end
