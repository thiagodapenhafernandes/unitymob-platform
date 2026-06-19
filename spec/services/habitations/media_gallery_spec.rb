require "rails_helper"

RSpec.describe Habitations::MediaGallery do
  describe "#api_media_pictures" do
    it "usa fotos anexadas como fonte principal e deixa API/Vista apenas como fallback" do
      habitation = create(
        :habitation,
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

      expect(api_pictures.map { |_pic, index, _url| index }).to eq([2])
      expect(api_pictures.map { |_pic, _index, url| url }).to eq(["https://cdn.vista.test/imoveis/1/fallback.jpg"])
    end
  end
end
