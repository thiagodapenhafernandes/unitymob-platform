require "rails_helper"

RSpec.describe HomeSections::Showcase do
  let(:tenant) { create(:admin_user, :admin).tenant }
  let!(:picked) { create(:habitation, tenant: tenant, exibir_no_site_flag: true) }
  let!(:others) { create_list(:habitation, 3, tenant: tenant, exibir_no_site_flag: true) }
  let(:section) do
    tenant.home_sections.new(section_type: :featured_properties, title: "Vitrine", property_filters: { "exibir_no_site" => "1", "selected_property_ids" => [picked.id] })
  end

  it "com imóveis escolhidos, só eles aparecem e os filtros são ignorados" do
    split = described_class.new(section, habitations: tenant.habitations).property_split

    expect(split[:manual]).to eq([picked.id])
    expect(split[:automatic]).to eq([])
  end

  it "escolhidos aparecem mesmo que não batam com os filtros (ex.: venda/locação)" do
    section.property_filters = { "locacao" => "1", "selected_property_ids" => [picked.id] }

    expect(described_class.new(section, habitations: tenant.habitations).property_ids).to eq([picked.id])
  end

  it "sem escolhidos, os filtros montam a vitrine" do
    section.property_filters = { "exibir_no_site" => "1" }
    split = described_class.new(section, habitations: tenant.habitations).property_split

    expect(split[:manual]).to eq([])
    expect(split[:automatic]).to match_array([picked.id, *others.map(&:id)])
  end

  it "respeita o limite menor da locação" do
    rental = tenant.home_sections.new(section_type: :featured_properties, property_filters: { "locacao" => "1" })
    plain = tenant.home_sections.new(section_type: :featured_properties)

    expect(described_class.new(rental, habitations: tenant.habitations).limit).to eq(described_class::RENTAL_LIMIT)
    expect(described_class.new(plain, habitations: tenant.habitations).limit).to eq(described_class::PROPERTY_LIMIT)
  end

  it "ignora escolhidos que não existem ou não estão disponíveis" do
    section.property_filters = { "selected_property_ids" => [0, 999_999] }

    expect(described_class.new(section, habitations: tenant.habitations).property_split[:manual]).to eq([])
  end

  it "em vídeos em destaque, completa a vitrine apenas com imóveis com vídeo" do
    with_video = create(:habitation, tenant:, videos: ["https://cdn.example.com/video.mp4"])
    with_youtube_id = create(:habitation, tenant:, videos: ["_2SaTVBZn0o"])
    with_tour = create(:habitation, tenant:, videos: ["https://my.matterport.com/show/?m=bvyrLMgmVHj"])
    with_blank_video = create(:habitation, tenant:, videos: ["", ""])
    without_video = create(:habitation, tenant:, videos: [])
    videos = tenant.home_sections.new(section_type: :featured_videos, title: "Vídeos")

    ids = described_class.new(videos, habitations: tenant.habitations).property_ids

    expect(ids).to include(with_video.id, with_youtube_id.id)
    expect(ids).not_to include(with_tour.id, with_blank_video.id, without_video.id)
  end
end
