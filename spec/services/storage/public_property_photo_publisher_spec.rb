require "rails_helper"

RSpec.describe Storage::PublicPropertyPhotoPublisher do
  around do |example|
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = original_cache
  end

  it "escopa estatísticas, busca e pendências pelo tenant" do
    current_tenant = Tenant.create!(name: "Tenant storage #{SecureRandom.hex(3)}", slug: "tenant-storage-#{SecureRandom.hex(3)}")
    other_tenant = Tenant.create!(name: "Outro storage #{SecureRandom.hex(3)}", slug: "outro-storage-#{SecureRandom.hex(3)}")
    current_habitation = create(:habitation, tenant: current_tenant, codigo: "PHOTO-CUR", titulo_anuncio: "Foto tenant atual")
    other_habitation = create(:habitation, tenant: other_tenant, codigo: "PHOTO-OUT", titulo_anuncio: "Foto outro tenant")
    attach_photo(current_habitation, "current.jpg")
    attach_photo(other_habitation, "other.jpg")

    publisher = described_class.new(tenant: current_tenant)

    expect(publisher.stats.total_attachments).to eq(1)
    expect(publisher.lookup("PHOTO-CUR").habitations).to eq([current_habitation])
    expect(publisher.lookup("PHOTO-OUT").habitations).to be_empty
    expect(publisher.pending_summary.total_habitations).to eq(1)
    expect(publisher.pending_summary.sample.map(&:habitation)).to eq([current_habitation])
  end

  it "não publica attachment de imóvel de outro tenant" do
    current_tenant = Tenant.create!(name: "Tenant attachment #{SecureRandom.hex(3)}", slug: "tenant-attachment-#{SecureRandom.hex(3)}")
    other_tenant = Tenant.create!(name: "Outro attachment #{SecureRandom.hex(3)}", slug: "outro-attachment-#{SecureRandom.hex(3)}")
    other_habitation = create(:habitation, tenant: other_tenant, codigo: "PHOTO-ATTACH-OUT")
    attach_photo(other_habitation, "other.jpg")
    attachment = other_habitation.photos.attachments.first

    result = described_class.new(tenant: current_tenant).publish_attachment_id(attachment.id)

    expect(result.failed).to eq(1)
    expect(result.errors.join).to include("não encontrado")
  end

  it "mantém progresso em cache separado por tenant" do
    current_tenant = Tenant.create!(name: "Tenant progress #{SecureRandom.hex(3)}", slug: "tenant-progress-#{SecureRandom.hex(3)}")
    other_tenant = Tenant.create!(name: "Outro progress #{SecureRandom.hex(3)}", slug: "outro-progress-#{SecureRandom.hex(3)}")

    described_class.write_progress({ status: "running", total: 10, processed: 5 }, tenant: current_tenant)

    expect(described_class.progress(tenant: current_tenant)[:status]).to eq("running")
    expect(described_class.progress(tenant: other_tenant)[:status]).to eq("idle")
  end

  def attach_photo(habitation, filename)
    habitation.photos.attach(
      io: StringIO.new("photo"),
      filename: filename,
      content_type: "image/jpeg"
    )
  end
end
