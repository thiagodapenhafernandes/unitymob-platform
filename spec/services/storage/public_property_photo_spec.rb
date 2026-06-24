require "rails_helper"

RSpec.describe Storage::PublicPropertyPhoto do
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
