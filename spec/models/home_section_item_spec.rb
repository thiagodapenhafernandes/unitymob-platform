require "rails_helper"

RSpec.describe HomeSectionItem do
  it "bloqueia arquivo que não é vídeo no item manual da Home" do
    tenant = Tenant.create!(name: "Conta Vídeo #{SecureRandom.hex(3)}", slug: "conta-video-#{SecureRandom.hex(3)}")
    section = tenant.home_sections.create!(section_type: "featured_videos", title: "Vídeos", active: true)
    item = section.home_section_items.build(source_type: "upload", title: "Tour", active: true)

    item.video_file.attach(
      io: StringIO.new("fake image"),
      filename: "fake.png",
      content_type: "image/png"
    )

    expect(item).not_to be_valid
    expect(item.errors[:video_file]).to be_present
  end

  it "aceita arquivo de vídeo suportado no item manual da Home" do
    tenant = Tenant.create!(name: "Conta MP4 #{SecureRandom.hex(3)}", slug: "conta-mp4-#{SecureRandom.hex(3)}")
    section = tenant.home_sections.create!(section_type: "featured_videos", title: "Vídeos", active: true)
    item = section.home_section_items.build(source_type: "upload", title: "Tour", active: true)

    item.video_file.attach(
      io: StringIO.new("fake video"),
      filename: "tour.mp4",
      content_type: "video/mp4"
    )

    expect(item).to be_valid
  end
end
