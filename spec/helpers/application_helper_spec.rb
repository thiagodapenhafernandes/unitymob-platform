require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  describe "#public_image_url" do
    before do
      allow(Storage::PublicPropertyPhoto).to receive(:public_base_url).and_return("https://cdn.saluteimoveis.com.br")
    end

    it "não expõe URLs internas do Active Storage como imagem pública" do
      url = "https://143.110.138.67/rails/active_storage/blobs/redirect/signed/file.jpg"

      expect(helper.public_image_url(url)).to be_nil
    end

    it "não mantém URLs externas fora do CDN configurado" do
      url = "https://cdn.vistahost.com.br/salute/foto.jpg"

      expect(helper.public_image_url(url)).to be_nil
    end

    it "mantém URLs do CDN configurado" do
      url = "https://cdn.saluteimoveis.com.br/foto.jpg"

      expect(helper.public_image_url(url)).to eq(url)
    end

    it "gera URL de CDN para blobs publicados" do
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("image"),
        filename: "foto.jpg",
        content_type: "image/jpeg"
      )
      allow(Storage::PublicPropertyPhoto).to receive(:public_url_for_blob).with(blob).and_return("https://cdn.saluteimoveis.com.br/#{blob.key}")

      expect(helper.public_image_url(blob)).to eq("https://cdn.saluteimoveis.com.br/#{blob.key}")
    end

    it "gera proxy do Active Storage para anexos privados diretos" do
      setting = HomeSetting.instance
      setting.hero_background_desktop.attach(
        io: StringIO.new("image"),
        filename: "hero.jpg",
        content_type: "image/jpeg"
      )
      attachment = setting.hero_background_desktop.attachment
      allow(Storage::PublicPropertyPhoto).to receive(:public_url_for_attachment).with(attachment).and_return(nil)

      result = helper.public_image_url(setting.hero_background_desktop)

      expect(result).to include("/rails/active_storage/blobs/proxy/")
      expect(result).to end_with("/hero.jpg")
    end
  end
end
