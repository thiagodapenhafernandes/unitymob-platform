require "rails_helper"

RSpec.describe Storage::PublicPropertyPhoto do
  it "usa o bucket original para blobs do serviço legado" do
    object = double(public_url: "https://imob.sfo3.digitaloceanspaces.com/hero")
    service = double
    blob = double(key: "hero", service_name: "do_spaces", service: service)
    allow(described_class).to receive(:s3_blob?).with(blob).and_return(true)
    allow(service).to receive(:object_for).with("hero").and_return(object)
    expect(described_class).not_to receive(:public_base_url)

    expect(described_class.public_url_for_blob(blob)).to eq(object.public_url)
  end

  describe ".public_attachment?" do
    before do
      allow(described_class).to receive(:public_photos_enabled?).and_return(true)
    end

    it "considera pública apenas foto vinculada ao imóvel" do
      attachment = ActiveStorage::Attachment.new(record_type: "Habitation", name: "photos")

      expect(described_class.public_attachment?(attachment)).to be(true)
    end

    it "não considera VistaFileAsset como fonte pública direta" do
      attachment = ActiveStorage::Attachment.new(record_type: "VistaFileAsset", name: "file")

      expect(described_class.public_attachment?(attachment)).to be(false)
    end
  end
end
