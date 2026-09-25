require "rails_helper"

RSpec.describe Storage::WarmPublicVariantsJob, type: :job do
  around do |example|
    previous = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
    Rails.cache = previous
  end

  let(:tenant) { Tenant.create!(name: "Warmer #{SecureRandom.hex(3)}", slug: "warmer-#{SecureRandom.hex(3)}") }

  def attach_photo(property)
    property.photos.attach(
      io: File.open(Rails.root.join("spec/fixtures/files/watermark.png")),
      filename: "foto.png",
      content_type: "image/png"
    )
  end

  it "enfileira transforms faltantes das fotos ativas e não duplica na revarredura" do
    property = create(:habitation, tenant: tenant)
    attach_photo(property)
    expect(Habitation.active.exists?(property.id)).to be(true)

    expect { described_class.perform_now }
      .to have_enqueued_job(Storage::TransformVariantJob).at_least(:once)

    expect { described_class.perform_now }
      .not_to have_enqueued_job(Storage::TransformVariantJob)
  end

  it "cobre os sets da galeria e dos banners do detalhe" do
    expect(described_class::SETS).to include(
      { resize_to_limit: [1200, 900], format: :webp },
      { resize_to_limit: [800, 600], format: :webp },
      { resize_to_limit: [480, 360], format: :webp },
      { resize_to_fill: [720, 520], format: :webp },
      { resize_to_limit: [1440, 360] },
      { resize_to_limit: [768, 360] },
      { resize_to_fill: [1400, 820], format: :webp },
      { resize_to_limit: [640, 1138], format: :webp },
      { resize_to_fill: [720, 860], format: :webp },
      { resize_to_fill: [560, 640], format: :webp }
    )
  end

  it "ignora fotos de imóveis inativos" do
    property = create(:habitation, tenant: tenant, status: "Inativo", exibir_no_site_flag: false)
    attach_photo(property)
    expect(Habitation.active.exists?(property.id)).to be(false)

    expect { described_class.perform_now }
      .not_to have_enqueued_job(Storage::TransformVariantJob)
  end
end
