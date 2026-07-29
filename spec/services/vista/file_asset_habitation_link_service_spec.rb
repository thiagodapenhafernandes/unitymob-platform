require "rails_helper"

RSpec.describe Vista::FileAssetHabitationLinkService do
  it "links existing property assets to imported habitations without resetting their status" do
    batch = VistaImportBatch.create!(dump_dir: "tmp/dump", status: "completed")
    habitation = create(:habitation, codigo: "1001", vista_import_batch_id: batch.id)
    asset = VistaFileAsset.create!(
      vista_import_batch: batch,
      table_name: "CDIMIM",
      kind: "property_photo",
      status: "downloaded",
      codigo_imovel: "1001",
      source_path: "1001/foto.jpg",
      source_url: "https://cdn.example.com/1001/foto.jpg",
      filename: "foto.jpg"
    )

    result = described_class.new(batch: batch, dry_run: false, tenant: habitation.tenant).call

    expect(result.linked).to eq(1)
    expect(asset.reload.habitation).to eq(habitation)
    expect(asset.status).to eq("downloaded")
  end

  it "links assets by property code inside the tenant even when the habitation came from another batch" do
    asset_batch = VistaImportBatch.create!(dump_dir: "tmp/dump-assets", status: "completed")
    property_batch = VistaImportBatch.create!(dump_dir: "tmp/dump-property", status: "completed")
    tenant = Tenant.default
    other_tenant = Tenant.create!(name: "Outro tenant #{SecureRandom.hex(3)}", slug: "outro-tenant-#{SecureRandom.hex(3)}")
    habitation = create(:habitation, tenant: tenant, codigo: "8623", vista_import_batch_id: property_batch.id)
    create(:habitation, tenant: other_tenant, codigo: "8623", vista_import_batch_id: property_batch.id)
    asset = VistaFileAsset.create!(
      vista_import_batch: asset_batch,
      table_name: "CDIMDC",
      kind: "property_document",
      status: "pending",
      codigo_imovel: "8623",
      source_path: "8623/autorizacao.pdf",
      source_url: "https://cdn.example.com/8623/autorizacao.pdf",
      filename: "autorizacao.pdf"
    )

    result = described_class.new(batch: asset_batch, dry_run: false, tenant: tenant).call

    expect(result.linked).to eq(1)
    expect(asset.reload.habitation).to eq(habitation)
  end

  it "requires a tenant to avoid linking assets across accounts by code only" do
    batch = VistaImportBatch.create!(dump_dir: "tmp/dump-no-tenant", status: "completed")

    expect { described_class.new(batch: batch, dry_run: true, tenant: nil).call }
      .to raise_error(ArgumentError, "Tenant obrigatório para vincular anexos Vista")
  end
end
