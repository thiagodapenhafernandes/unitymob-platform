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

    result = described_class.new(batch: batch, dry_run: false).call

    expect(result.linked).to eq(1)
    expect(asset.reload.habitation).to eq(habitation)
    expect(asset.status).to eq("downloaded")
  end
end
