require "rails_helper"

RSpec.describe Storage::PublicCdnImageUrl, "cache de existência de variante" do
  around do |example|
    previous = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
    Rails.cache = previous
  end

  let(:transformations) { { resize_to_limit: [100, 100] } }

  def attach_photo(record)
    record.photos.attach(
      io: File.open(Rails.root.join("spec/fixtures/files/watermark.png")),
      filename: "foto.png",
      content_type: "image/png"
    )
    record.photos.first
  end

  def process_variant(attachment)
    blob = attachment.blob
    digest = blob.variant(**transformations).variation.digest
    record = ActiveStorage::VariantRecord.create!(blob_id: blob.id, variation_digest: digest)
    record.image.attach(
      io: File.open(Rails.root.join("spec/fixtures/files/watermark.png")),
      filename: "variante.png",
      content_type: "image/png"
    )
    record
  end

  it "consulta o serviço uma vez e serve do cache em seguida" do
    property = create(:habitation)
    attachment = attach_photo(property)
    process_variant(attachment)

    service_spy = attachment.blob.service
    allow(service_spy).to receive(:exist?).and_call_original

    first = described_class.resolve(attachment, **transformations)
    second = described_class.resolve(attachment, **transformations)

    expect(first).to be_present
    expect(second).to eq(first)
    expect(service_spy).to have_received(:exist?).once
  end

  it "entrega a derivada publicada diretamente e respeita a política da conta" do
    attachment = attach_photo(create(:habitation))
    variant_record = process_variant(attachment)
    variant_blob = variant_record.image.blob
    variant_blob.update!(metadata: { "public_web_image" => true })
    allow(Storage::PublicPropertyPhoto).to receive(:public_photos_enabled?).and_return(true)
    allow(Storage::PublicPropertyPhoto).to receive(:public_url_for_blob).with(variant_blob).and_return("https://cdn.example.com/derivada.webp")
    expect(described_class.resolve(attachment, **transformations)).to eq("https://cdn.example.com/derivada.webp")

    allow(Storage::PublicPropertyPhoto).to receive(:public_photos_enabled?).and_return(false)
    expect(described_class.resolve(attachment, **transformations)).to start_with("/rails/active_storage/representations/")
  end
end
