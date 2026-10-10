require "rails_helper"

RSpec.describe Vista::FileAssetTenantBackfill do
  let(:tenant) { Tenant.create!(name: "Tenant backfill #{SecureRandom.hex(3)}", slug: "tenant-backfill-#{SecureRandom.hex(3)}") }
  let(:habitation) { create(:habitation, tenant: tenant, codigo: "BFILL-1") }
  let(:batch) { VistaImportBatch.create!(dump_dir: "api:vista", status: "completed") }

  def legacy_asset(attrs = {})
    VistaFileAsset.create!({
      vista_import_batch: batch, tenant_id: nil, table_name: "API_FOTO",
      source_path: "api/foto/#{SecureRandom.hex(4)}.jpg", kind: "property_photo",
      status: "pending", filename: "foto.jpg", habitation: habitation, codigo_imovel: habitation.codigo
    }.merge(attrs))
  end

  it "preenche tenant_id a partir do imóvel e é idempotente" do
    asset = legacy_asset

    result = described_class.new(dry_run: false).call

    expect(asset.reload.tenant_id).to eq(tenant.id)
    expect(result.updated).to eq(1)
    rerun = described_class.new(dry_run: false).call
    expect(rerun.updated).to eq(0)
    expect(rerun.scanned).to eq(0)
  end

  it "dry run não altera nada e reporta pendentes" do
    legacy_asset

    result = described_class.new(dry_run: true).call

    expect(VistaFileAsset.where(tenant_id: nil).count).to eq(1)
    expect(result.pending).to eq(1)
    expect(result.updated).to eq(0)
  end

  it "pula órfãos sem imóvel e segue o lote" do
    legacy_asset(habitation: nil, codigo_imovel: "ORPHAN")
    ok = legacy_asset

    result = described_class.new(dry_run: false).call

    expect(result.skipped_orphan).to eq(1)
    expect(ok.reload.tenant_id).to eq(tenant.id)
  end

  it "conta conflito de unicidade sem interromper" do
    legacy_asset(source_path: "api/foto/dup.jpg")
    VistaFileAsset.create!(
      vista_import_batch: batch, tenant_id: tenant.id, table_name: "API_FOTO",
      source_path: "api/foto/dup.jpg", kind: "property_photo", status: "pending",
      filename: "dup.jpg", habitation: habitation, codigo_imovel: habitation.codigo
    )

    result = described_class.new(dry_run: false).call

    expect(result.conflicts).to eq(1)
    expect(result.updated).to eq(0)
  end
end
