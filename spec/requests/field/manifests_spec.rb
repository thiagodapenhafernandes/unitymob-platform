require 'rails_helper'

RSpec.describe "Field::Manifests", type: :request do
  describe "GET /field/manifest" do
    before do
      # Rails config.hosts whitelist não inclui www.example.com (default do Rack test).
      host! "localhost"
    end

    it "responde JSON com payload do PWA" do
      get "/field/manifest.json"
      expect(response).to have_http_status(:ok)
      payload = JSON.parse(response.body)
      expect(payload["name"]).to eq("Salute Imóveis — Campo")
      expect(payload["scope"]).to eq("/field/")
      expect(payload["start_url"]).to eq("/field")
      expect(payload["display"]).to eq("standalone")
      expect(payload["icons"].map { |i| i["sizes"] }).to match_array(%w[192x192 512x512])
    end

    it "não exige autenticação (manifest pode ser lido pelo browser)" do
      get "/field/manifest.json"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "service worker file" do
    it "está acessível estaticamente em /field-service-worker.js" do
      path = Rails.root.join("public", "field-service-worker.js")
      expect(File.exist?(path)).to be true
      expect(File.read(path)).to include("field-ping-queue")
    end
  end
end
