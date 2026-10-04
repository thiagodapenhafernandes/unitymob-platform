require "rails_helper"

RSpec.describe Storage::PublicPropertyPhoto do
  it "usa o bucket original para blobs do serviço legado" do
    object = double(public_url: "https://imob.sfo3.digitaloceanspaces.com/hero")
    service = double
    blob = double(metadata: {}, key: "hero", service_name: "do_spaces", service: service)
    allow(described_class).to receive(:s3_blob?).with(blob).and_return(true)
    allow(service).to receive(:object_for).with("hero").and_return(object)
    expect(described_class).not_to receive(:public_base_url)

    expect(described_class.public_url_for_blob(blob)).to eq(object.public_url)
  end

  it "usa CDN apenas para a derivada web pública legada, preservando bucket e chave" do
    object = double(public_url: "https://imob.sfo3.digitaloceanspaces.com/folder/hero.webp")
    service = double
    blob = double(metadata: { "public_web_image" => true, "public_web_cdn" => true }, key: "folder/hero.webp", service_name: "do_spaces", service: service)
    allow(described_class).to receive(:s3_blob?).with(blob).and_return(true)
    allow(service).to receive(:object_for).with(blob.key).and_return(object)
    expect(described_class.public_url_for_blob(blob)).to eq("https://imob.sfo3.cdn.digitaloceanspaces.com/folder/hero.webp")
  end

  it "mantém a origem quando o CDN não responde com sucesso" do
    object = double(public_url: "https://imob.sfo3.digitaloceanspaces.com/hero.webp")
    service = double
    blob = double(key: "hero.webp", service_name: "do_spaces", service: service)
    allow(service).to receive(:object_for).with(blob.key).and_return(object)
    http = double
    allow(Net::HTTP).to receive(:start).and_yield(http)
    allow(http).to receive(:head).with("/hero.webp").and_return(Net::HTTPNotFound.new("1.1", "404", "Not Found"))
    expect(described_class.public_cdn_available?(blob)).to be(false)
  end

  it "configura cache somente na publicação explícita, preservando tipo e metadados" do
    object = double(bucket_name: "public-images", metadata: { "owner" => "tenant" }, content_type: "image/webp", content_disposition: "inline")
    service = double
    blob = double(key: "folder/web.webp", service: service)
    allow(service).to receive(:object_for).with(blob.key).and_return(object)
    expect(object).to receive(:copy_from).with(
      copy_source: "public-images/folder/web.webp", metadata_directive: "REPLACE",
      metadata: { "owner" => "tenant" }, content_type: "image/webp", content_disposition: "inline",
      cache_control: "public, max-age=31536000, immutable", acl: "public-read"
    )
    described_class.cache_public_blob!(blob)
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
