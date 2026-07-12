require "rails_helper"

RSpec.describe Habitations::MediaGallery do
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
