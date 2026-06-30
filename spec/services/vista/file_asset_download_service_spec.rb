require "rails_helper"

RSpec.describe Vista::FileAssetDownloadService do
  before do
    ActiveStorage::Blob.services.fetch(:local).delete_prefixed("vista")
  end

  it "uploads with a deterministic key and stores reusable storage metadata" do
    batch = VistaImportBatch.create!(dump_dir: "tmp/dump", status: "completed")
    habitation = create(:habitation, codigo: "1001")
    asset = VistaFileAsset.create!(
      vista_import_batch: batch,
      habitation: habitation,
      table_name: "CDIMIM",
      kind: "property_photo",
      status: "pending",
      codigo_imovel: "1001",
      source_path: "1001/foto.jpg",
      source_url: "https://cdn.example.com/1001/foto.jpg",
      filename: "foto.jpg",
      active_storage_name: "photos"
    )

    service = described_class.new(scope: VistaFileAsset.where(id: asset.id), dry_run: false)
    allow(service).to receive(:download).and_return(StringIO.new("image-body"))

    result = service.call

    expect(result.downloaded).to eq(1)
    expect(asset.reload).to have_attributes(
      status: "downloaded",
      active_storage_key: "vista/property_photo/1001/#{asset.id}-foto.jpg",
      storage_byte_size: 10,
      storage_service_name: "local"
    )
    expect(asset.storage_checksum).to be_present
    expect(asset.active_storage_attachment).to be_present
    expect(habitation.photos.attachments.first.blob.key).to eq(asset.active_storage_key)
  end

  it "reuses a preexisting blob row and uploads the missing object" do
    batch = VistaImportBatch.create!(dump_dir: "tmp/dump", status: "completed")
    habitation = create(:habitation, codigo: "7232")
    asset = VistaFileAsset.create!(
      vista_import_batch: batch,
      habitation: habitation,
      table_name: "CDIMIM",
      kind: "property_photo",
      status: "pending",
      codigo_imovel: "7232",
      source_path: "7232/foto.jpg",
      source_url: "https://cdn.example.com/7232/foto.jpg",
      filename: "foto.jpg",
      active_storage_name: "photos"
    )
    key = "vista/property_photo/7232/#{asset.id}-foto.jpg"
    ActiveStorage::Blob.create_before_direct_upload!(
      key: key,
      filename: asset.filename,
      byte_size: 1,
      checksum: Base64.strict_encode64(Digest::MD5.digest("x")),
      content_type: "image/jpeg",
      service_name: ActiveStorage::Blob.service.name
    )

    service = described_class.new(scope: VistaFileAsset.where(id: asset.id), dry_run: false)
    allow(service).to receive(:download).and_return(StringIO.new("image-body"))

    result = service.call

    expect(result.downloaded).to eq(1)
    expect(asset.reload).to have_attributes(
      status: "downloaded",
      active_storage_key: key,
      storage_byte_size: 10
    )
    expect(asset.active_storage_attachment).to be_present
    expect(ActiveStorage::Blob.services.fetch(asset.reload.storage_service_name.to_sym).exist?(key)).to be(true)
  end
end
