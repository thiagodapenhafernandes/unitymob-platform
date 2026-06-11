require "rails_helper"

RSpec.describe Vista::FileAssetIndexService do
  it "indexes unique file references and links property files to habitations" do
    batch = VistaImportBatch.create!(dump_dir: "tmp/dump", status: "completed")
    habitation = create(:habitation, codigo: "1001")

    2.times do |index|
      VistaRawRecord.create!(
        vista_import_batch: batch,
        table_name: "CDIMIM",
        row_index: index + 1,
        codigo_imovel: "1001",
        payload: {
          "CODIGO" => "1001",
          "ORDEM" => "1",
          "FILE_PATH" => "1001/foto.jpg"
        }
      )
    end

    result = described_class.new(batch: batch, dry_run: false).call

    expect(result.indexed).to eq(1)
    expect(result.skipped).to eq(1)
    asset = VistaFileAsset.find_by!(source_path: "1001/foto.jpg")
    expect(asset.habitation).to eq(habitation)
    expect(asset.kind).to eq("property_photo")
    expect(asset.active_storage_name).to eq("photos")
  end

  it "does not index youtube video records as physical photo files" do
    batch = VistaImportBatch.create!(dump_dir: "tmp/dump", status: "completed")

    VistaRawRecord.create!(
      vista_import_batch: batch,
      table_name: "CDIMVD",
      row_index: 1,
      codigo_imovel: "1001",
      payload: {
        "CODIGO" => "1001",
        "TIPO" => "youtube",
        "FILE_PATH" => "SehxLiJB7NA"
      }
    )

    result = described_class.new(batch: batch, dry_run: false).call

    expect(result.indexed).to eq(0)
    expect(VistaFileAsset.count).to eq(0)
  end
end
