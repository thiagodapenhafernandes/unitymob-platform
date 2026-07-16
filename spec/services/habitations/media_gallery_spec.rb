require "rails_helper"

RSpec.describe Habitations::MediaGallery do
  before do
    allow(Storage::PublicPropertyPhoto).to receive(:public_base_url).and_return("https://cdn.saluteimoveis.com.br")
  end

  describe "#development_media_sources" do
    it "inclui fotos públicas do empreendimento vinculado mesmo quando a unidade tem foto própria" do
      development = create(
        :habitation,
        codigo: "DEV-MEDIA-#{SecureRandom.hex(6)}",
        tipo: "Empreendimento",
        pictures: [{ "url" => "https://cdn.saluteimoveis.com.br/empreendimento.jpg" }]
      )
      unit = create(
        :habitation,
        codigo: "UNIT-MEDIA-#{SecureRandom.hex(6)}",
        codigo_empreendimento: development.codigo,
        use_development_photos_flag: true,
        pictures: []
      )
      unit.photos.attach(io: StringIO.new("foto unidade"), filename: "unidade.jpg", content_type: "image/jpeg")

      gallery = described_class.new(unit.reload)

      expect(gallery.attached_media_photos.size).to eq(1)
      expect(gallery.development_media_sources.map { |source| source["url"] }).to eq(["https://cdn.saluteimoveis.com.br/empreendimento.jpg"])
      expect(gallery.media_gallery_count).to eq(2)
    end
  end

  describe "#api_media_pictures" do
    it "mantém URLs DWV como fonte operacional e elimina duplicatas materializadas" do
      habitation = create(
        :habitation,
        codigo: "DWV-MEDIA-#{SecureRandom.hex(6)}",
        imovel_dwv: "Sim",
        pictures: [
          { "url" => "https://cdn.vista.test/imoveis/1/posicao-um.jpg" },
          { "url" => "https://cdn.vista.test/imoveis/1/foto-local.jpg" },
          { "url" => "https://cdn.vista.test/imoveis/1/fallback.jpg" }
        ]
      )
      habitation.photos.attach(
        io: StringIO.new("imagem local"),
        filename: "foto-local.jpg",
        content_type: "image/jpeg"
      )

      api_pictures = described_class.new(habitation.reload).api_media_pictures

      expect(api_pictures.map { |_pic, index, _url| index }).to eq([0, 2])
      expect(api_pictures.map { |_pic, _index, url| url }).to eq([
        "https://cdn.vista.test/imoveis/1/posicao-um.jpg",
        "https://cdn.vista.test/imoveis/1/fallback.jpg"
      ])
      expect(api_pictures.map { |_pic, _index, url| File.basename(URI.parse(url).path) }).not_to include("foto-local.jpg")
    end

    it "não usa payload remoto de imóvel que não pertence ao DWV" do
      habitation = create(:habitation, codigo: "LOCAL-MEDIA-#{SecureRandom.hex(6)}", imovel_dwv: "Nao", pictures: [{ "url" => "https://cdn.vista.test/foto.jpg" }])

      expect(described_class.new(habitation).api_media_pictures).to be_empty
    end
  end
end
