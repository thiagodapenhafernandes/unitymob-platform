require "rails_helper"

RSpec.describe Storage::PublicImageVariants do
  let(:tenant) { Tenant.create!(name: "Fotos Web", slug: "fotos-web-#{SecureRandom.hex(3)}") }
  let(:setting) { HomeSetting.instance(tenant: tenant) }

  def attach_image(record, name)
    record.public_send(name).attach(
      io: File.open(Rails.root.join("spec/fixtures/files/watermark.png")),
      filename: "original.png", content_type: "image/png"
    )
    record.public_send(name).blob
  end

  it "gera WebP na fila de mídia, preserva o PNG e publica apenas a derivada" do
    blob = attach_image(setting, :hero_background_desktop)
    original_key = blob.key
    original_checksum = blob.checksum
    options = described_class::HERO.last
    allow(Storage::PublicPropertyPhoto).to receive(:public_photos_enabled?).with(tenant: tenant).and_return(true)
    allow(Storage::PublicPropertyPhoto).to receive(:publish_blob!).and_return(true)
    version_before = PublicSite::PageVersion.current(tenant.id)

    ActiveStorage::TransformJob.perform_now(blob, options)

    variant_blob = blob.variant(**options).image.blob
    expect(variant_blob.content_type).to eq("image/webp")
    expect(variant_blob.metadata["public_web_image"]).to be(true)
    expect(PublicSite::PageVersion.current(tenant.id)).not_to eq(version_before)
    expect(Storage::PublicPropertyPhoto).to have_received(:publish_blob!).with(variant_blob)
    expect(blob.reload.attributes.values_at("key", "checksum", "content_type")).to eq([original_key, original_checksum, "image/png"])
    expect(ActiveStorage::TransformJob.new.queue_name).to eq("media")
  end

  it "não publica anexos privados, mesmo com os mesmos tamanhos" do
    blob = attach_image(setting, :navigation_menu_image)
    expect(Storage::PublicPropertyPhoto).not_to receive(:publish_blob!)
    described_class.publish(blob, described_class::HERO.last)
  end

  it "respeita a configuração da conta que proíbe fotos públicas" do
    blob = attach_image(setting, :hero_background_desktop)
    allow(Storage::PublicPropertyPhoto).to receive(:public_photos_enabled?).with(tenant: tenant).and_return(false)
    expect(Storage::PublicPropertyPhoto).not_to receive(:publish_blob!)
    described_class.publish(blob, described_class::HERO.last)
  end

  it "mantém o fallback quando o storage não permite publicação" do
    blob = attach_image(setting, :hero_background_desktop)
    options = described_class::HERO.last
    blob.variant(**options).processed
    allow(Storage::PublicPropertyPhoto).to receive(:public_photos_enabled?).and_return(true)
    allow(Storage::PublicPropertyPhoto).to receive(:publish_blob!).and_return(false)
    described_class.publish(blob, options)
    expect(blob.variant(**options).image.blob.metadata["public_web_image"]).not_to be(true)
  end
end
