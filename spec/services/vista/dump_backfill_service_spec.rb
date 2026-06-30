require "rails_helper"

RSpec.describe Vista::DumpBackfillService do
  around do |example|
    previous_tenant = Current.tenant
    example.run
  ensure
    Current.tenant = previous_tenant
  end

  it "usa target scope apenas do Tenant corrente" do
    current_tenant = Tenant.create!(name: "Tenant back #{SecureRandom.hex(3)}", slug: "tenant-back-#{SecureRandom.hex(3)}")
    other_tenant = Tenant.create!(name: "Outro back #{SecureRandom.hex(3)}", slug: "outro-back-#{SecureRandom.hex(3)}")
    current_habitation = create(:habitation, tenant: current_tenant, codigo: "BACK-HAB-1", last_sync_message: "Importado do dump Vista")
    create(:habitation, tenant: other_tenant, codigo: "BACK-HAB-2", last_sync_message: "Importado do dump Vista")

    Current.tenant = current_tenant
    service = described_class.new(dump_dir: Rails.root, dry_run: true, only_imported: true)

    expect(service.send(:target_scope).pluck(:id)).to eq([current_habitation.id])
  end
end
