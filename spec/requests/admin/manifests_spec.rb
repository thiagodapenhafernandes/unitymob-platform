require "rails_helper"

RSpec.describe "Admin::Manifests", type: :request do
  describe "GET /admin/manifest" do
    before do
      host! "localhost"
    end

    it "mantém todas as rotas mobile do mesmo domínio dentro do PWA" do
      get "/admin/manifest.json"

      expect(response).to have_http_status(:ok)

      payload = JSON.parse(response.body)
      expect(payload["id"]).to eq("/admin")
      expect(payload["start_url"]).to eq("/admin/")
      expect(payload["scope"]).to eq("/")
      expect(payload["display"]).to eq("standalone")
      expect(payload["icons"].map { |i| i["src"] }).to all(match(%r{\A/pwa-icon-(192|512)\?v=\d+\z}))
    end

    it "não exige autenticação" do
      get "/admin/manifest.json"

      expect(response).to have_http_status(:ok)
    end
  end
end
