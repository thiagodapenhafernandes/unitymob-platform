require "rails_helper"

RSpec.describe Storage::TransformVariantJob do
  it "processa a variante solicitada" do
    blob = instance_double(ActiveStorage::Blob, id: 123)
    variant = instance_double(ActiveStorage::VariantWithRecord)
    transformations = { "resize_to_fill" => [640, 480] }

    allow(blob).to receive(:variant).with(resize_to_fill: [640, 480]).and_return(variant)
    allow_any_instance_of(Storage::PublicCdnImageUrl).to receive(:verify_variant).and_return(true)
    expect(variant).to receive(:processed).and_return(variant)

    described_class.new.perform(blob, transformations)
  end

  it "regenera na fila uma variante ausente no storage" do
    blob = instance_double(ActiveStorage::Blob, id: 124)
    variant = instance_double(ActiveStorage::VariantWithRecord)
    resolver = instance_double(Storage::PublicCdnImageUrl)
    allow(blob).to receive(:variant).and_return(variant)
    allow(Storage::PublicCdnImageUrl).to receive(:new).and_return(resolver)
    expect(variant).to receive(:processed).twice.and_return(variant)
    expect(resolver).to receive(:verify_variant).with(variant).twice.and_return(false, true)
    expect(Storage::PublicImageVariants).to receive(:publish).with(blob, { "resize_to_fill" => [640, 480] })
    described_class.new.perform(blob, { "resize_to_fill" => [640, 480] })
  end

  it "coloca a variante em quarentena quando o blob falha na integridade" do
    blob = instance_double(ActiveStorage::Blob, id: 456)
    transformations = { "resize_to_fill" => [640, 480] }
    error = ActiveStorage::IntegrityError.new

    allow(blob).to receive(:variant).and_raise(error)
    expect(Storage::PublicCdnImageUrl).to receive(:mark_transform_failed).with(
      blob: blob,
      transformations: transformations,
      error: error
    )

    expect { described_class.new.perform(blob, transformations) }.to raise_error(ActiveStorage::IntegrityError)
  end

  it "descarta sem falhar quando o arquivo original não existe mais" do
    blob = instance_double(ActiveStorage::Blob, id: 789)
    transformations = { "resize_to_fill" => [640, 480] }
    error = ActiveStorage::FileNotFoundError.new

    allow(blob).to receive(:variant).and_raise(error)
    expect(Storage::PublicCdnImageUrl).to receive(:mark_transform_failed).with(
      blob: blob,
      transformations: transformations,
      error: error
    )

    expect(described_class.new.perform(blob, transformations)).to be_nil
  end
end
