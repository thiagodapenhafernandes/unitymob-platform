require "rails_helper"

RSpec.describe Storage::TransformVariantJob do
  it "processa a variante solicitada" do
    blob = instance_double(ActiveStorage::Blob, id: 123)
    variant = instance_double(ActiveStorage::VariantWithRecord)
    transformations = { "resize_to_fill" => [640, 480] }

    allow(blob).to receive(:variant).with(resize_to_fill: [640, 480]).and_return(variant)
    expect(variant).to receive(:processed)

    described_class.new.perform(blob, transformations)
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
end
