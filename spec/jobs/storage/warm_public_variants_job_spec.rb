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

  it "warms the same card profile served publicly instead of a duplicate legacy variant" do
    attach_photo(create(:habitation, tenant: tenant))

    expect { described_class.perform_now }
      .to have_enqueued_job(Storage::TransformVariantJob)
      .with(anything, Storage::PublicImageVariants::CARD.first)
    expect(described_class::SETS).not_to include(resize_to_fill: [360, 270], format: :webp)
  end

  it "limita os jobs enfileirados por varredura e continua do ponto em que parou" do
    stub_const("#{described_class}::MAX_ENQUEUE_PER_RUN", 5)
    attach_photo(create(:habitation, tenant: tenant))

    expect { described_class.perform_now }
      .to have_enqueued_job(Storage::TransformVariantJob).exactly(5).times

    expect { described_class.perform_now }
      .to have_enqueued_job(Storage::TransformVariantJob).exactly(5).times
  end

  it "cobre os sets da galeria e dos banners do detalhe" do
    expect(described_class::SETS).to include(
      { resize_to_limit: [1200, 900], format: :webp },
      { resize_to_limit: [800, 600], format: :webp },
      { resize_to_limit: [480, 360], format: :webp },
      { resize_to_fill: [720, 520], format: :webp },
      { resize_to_limit: [1440, 360] },
      { resize_to_limit: [768, 360] },
      { resize_to_limit: [640, 1138], format: :webp },
      { resize_to_fill: [720, 860], format: :webp },
      { resize_to_fill: [560, 640], format: :webp }
    )
  end

  it "cobre os tamanhos de miniatura/hero calculados pelo srcset (antes ausentes e vistos lentos em produção)" do
    expect(described_class::SETS).to include(
      { resize_to_fill: [360, 260], format: :webp },
      { resize_to_fill: [520, 376], format: :webp },
      { resize_to_fill: [640, 480], format: :webp },
      { resize_to_limit: [1920, 1440], format: :webp },
      { resize_to_limit: [640, 360], format: :webp },
      { resize_to_limit: [960, 540], format: :webp },
      { resize_to_limit: [1400, 788], format: :webp },
      { resize_to_limit: [520, 400], format: :webp }
    )
    expect(described_class::SETS).not_to include({ resize_to_fill: [1400, 820], format: :webp })
  end

  it "ignora fotos de imóveis inativos" do
    property = create(:habitation, tenant: tenant, status: "Inativo", exibir_no_site_flag: false)
    attach_photo(property)
    expect(Habitation.active.exists?(property.id)).to be(false)

    expect { described_class.perform_now }
      .not_to have_enqueued_job(Storage::TransformVariantJob)
  end
end
