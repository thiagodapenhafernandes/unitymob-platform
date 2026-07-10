require "rails_helper"

RSpec.describe PublicSite::CardPhotoPreloader do
  def attach_photos(habitation, count)
    count.times do |index|
      habitation.photos.attach(
        io: StringIO.new("photo-#{index}"),
        filename: "photo-#{index}.jpg",
        content_type: "image/jpeg"
      )
    end
  end

  it "loads only the requested number of photos per property" do
    habitation = create(:habitation)
    attach_photos(habitation, 8)
    record = Habitation.find(habitation.id)

    described_class.new([record], limit: 5).call

    expect(record.association(:photos_attachments)).to be_loaded
    expect(record.photos_attachments.size).to eq(5)
    expect(record.card_image_sources(5).size).to eq(5)
  end

  it "preserves explicit ordering and excludes hidden photos" do
    habitation = create(:habitation)
    attach_photos(habitation, 6)
    attachments = habitation.photos_attachments.order(:id).to_a
    habitation.update_columns(
      photo_ids_order: [attachments.fifth.id, attachments.second.id, attachments.first.id],
      site_hidden_photo_ids: [attachments.second.id]
    )
    record = Habitation.find(habitation.id)

    described_class.new([record], limit: 3).call

    expect(record.photos_attachments.map(&:id)).to eq([
      attachments.fifth.id,
      attachments.first.id,
      attachments.third.id
    ])
  end

  it "loads linked development photos with the same bound" do
    development = create(:habitation, tipo: "Empreendimento")
    attach_photos(development, 7)
    unit = create(
      :habitation,
      codigo_empreendimento: development.codigo,
      use_development_photos_flag: true,
      pictures: []
    )
    record = Habitation.where(id: unit.id).includes(:empreendimento).first

    described_class.new([record], limit: 5).call

    expect(record.empreendimento.photos_attachments.size).to eq(5)
  end

  it "fills the card with later visible photos when the first attachments are hidden" do
    habitation = create(:habitation)
    attach_photos(habitation, 9)
    attachments = habitation.photos_attachments.order(:id).to_a
    habitation.update_columns(site_hidden_photo_ids: attachments.first(5).map(&:id))
    record = Habitation.find(habitation.id)

    described_class.new([record], limit: 3).call

    expect(record.photos_attachments.map(&:id)).to eq(attachments.drop(5).first(3).map(&:id))
  end
end
