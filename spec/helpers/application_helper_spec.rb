require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  describe "#public_image_url" do
    it "remove host absoluto de URLs internas do Active Storage" do
      url = "https://143.110.138.67/rails/active_storage/blobs/redirect/signed/file.jpg"

      expect(helper.public_image_url(url)).to eq("/rails/active_storage/blobs/redirect/signed/file.jpg")
    end

    it "mantem URLs externas sem alterar" do
      url = "https://cdn.vistahost.com.br/salute/foto.jpg"

      expect(helper.public_image_url(url)).to eq(url)
    end

    it "gera caminho relativo para blobs do Active Storage" do
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("image"),
        filename: "foto.jpg",
        content_type: "image/jpeg"
      )

      expect(helper.public_image_url(blob)).to start_with("/rails/active_storage/blobs/redirect/")
    end

    it "gera caminho relativo para anexos Active Storage diretos" do
      setting = HomeSetting.instance
      setting.hero_background_desktop.attach(
        io: StringIO.new("image"),
        filename: "hero.jpg",
        content_type: "image/jpeg"
      )

      expect(helper.public_image_url(setting.hero_background_desktop)).to start_with("/rails/active_storage/blobs/redirect/")
    end
  end
end
