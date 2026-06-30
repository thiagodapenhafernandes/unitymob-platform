require "rails_helper"

RSpec.describe Vista::FileAssetIndexService do
  around do |example|
    previous_tenant = Current.tenant
    example.run
  ensure
    Current.tenant = previous_tenant
  end

  it "indexa assets usando apenas imóveis do Tenant corrente" do
    current_tenant = Tenant.create!(name: "Tenant asset #{SecureRandom.hex(3)}", slug: "tenant-asset-#{SecureRandom.hex(3)}")
    other_tenant = Tenant.create!(name: "Outro asset #{SecureRandom.hex(3)}", slug: "outro-asset-#{SecureRandom.hex(3)}")
    current_habitation = create(:habitation, tenant: current_tenant, codigo: "ASSET-HAB-1")
    create(:habitation, tenant: other_tenant, codigo: "ASSET-HAB-2")
    batch = VistaImportBatch.create!(dump_dir: "spec", status: "completed")
    record = batch.vista_raw_records.create!(
      table_name: "CDIMIM",
      row_index: 1,
      codigo_imovel: "ASSET-HAB-1",
      payload: { "FILE_PATH" => "foto.jpg", "ORDEM" => "1" }
    )

    Current.tenant = current_tenant
    service = described_class.new(batch: batch, dry_run: true)
    habitation_id_by_code = current_tenant.habitations.where.not(codigo: [nil, ""]).pluck(:codigo, :id).to_h

    attrs = service.send(:asset_attributes, record, habitation_id_by_code)

    expect(attrs[:habitation_id]).to eq(current_habitation.id)
  end
end
