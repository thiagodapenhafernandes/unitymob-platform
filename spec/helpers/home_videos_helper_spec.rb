require "rails_helper"

RSpec.describe HomeVideosHelper, type: :helper do
  describe "#home_video_payload" do
    it "normaliza YouTube para embed" do
      payload = helper.home_video_payload("https://www.youtube.com/watch?v=abc123")

      expect(payload[:provider]).to eq("youtube")
      expect(payload[:embed_url]).to include("youtube.com/embed/abc123")
      expect(payload[:poster_url]).to include("img.youtube.com/vi/abc123")
    end

    it "aceita ID puro do YouTube importado do legado" do
      payload = helper.home_video_payload("_2SaTVBZn0o")

      expect(payload[:provider]).to eq("youtube")
      expect(payload[:embed_url]).to include("youtube.com/embed/_2SaTVBZn0o")
    end

    it "normaliza Vimeo para embed" do
      payload = helper.home_video_payload("https://vimeo.com/123456")

      expect(payload[:provider]).to eq("vimeo")
      expect(payload[:embed_url]).to eq("https://player.vimeo.com/video/123456?autoplay=1")
    end

    it "normaliza Instagram para embed" do
      payload = helper.home_video_payload("https://www.instagram.com/reel/ABC123/")

      expect(payload[:provider]).to eq("instagram")
      expect(payload[:embed_url]).to eq("https://www.instagram.com/reel/ABC123/embed")
    end

    it "mantém MP4 direto para player nativo" do
      payload = helper.home_video_payload({ "url" => "https://cdn.example.com/imovel.mp4" })

      expect(payload[:provider]).to eq("direct")
      expect(payload[:direct_url]).to eq("https://cdn.example.com/imovel.mp4")
      expect(payload[:content_type]).to eq("video/mp4")
    end

    it "aceita URL relativa do ActiveStorage para upload salvo" do
      payload = helper.home_video_payload("/rails/active_storage/blobs/redirect/token/video.mp4")

      expect(payload[:provider]).to eq("direct")
      expect(payload[:direct_url]).to eq("/rails/active_storage/blobs/redirect/token/video.mp4")
    end

    it "ignora tour virtual e URL sem formato de vídeo reproduzível" do
      expect(helper.home_video_payload("https://my.matterport.com/show/?m=bvyrLMgmVHj")).to be_nil
      expect(helper.home_video_payload("https://tour360.example.com/index.html")).to be_nil
      expect(helper.home_video_payload("")).to be_nil
    end
  end
end
