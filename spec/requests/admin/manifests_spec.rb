require "rails_helper"

RSpec.describe "Admin::Manifests", type: :request do
  include Devise::Test::IntegrationHelpers

  describe "GET /admin/manifest" do
    before do
      host! "localhost"
    end

    it "mantém todas as rotas mobile do mesmo domínio dentro do PWA" do
      get "/admin/manifest.json"

      expect(response).to have_http_status(:ok)

      payload = JSON.parse(response.body)
      expect(payload["id"]).to eq("/admin?tenant=#{Tenant.public_for.slug}")
      expect(payload["start_url"]).to eq("/admin/")
      expect(payload["scope"]).to eq("/")
      expect(payload["display"]).to eq("standalone")
      expect(payload["icons"].map { |i| i["src"] }).to all(match(%r{\A/pwa-icon-(192|512)\?tenant=#{Tenant.public_for.slug}&v=\d+\z}))
      expect(response.headers["Cache-Control"]).to include("private")
      expect(response.headers["Vary"]).to include("Cookie")
    end

    it "usa identidade e icones do tenant autenticado" do
      tenant = Tenant.create!(name: "Conexão Imobiliária", slug: "conexao-imobiliaria-#{SecureRandom.hex(3)}")
      other_tenant = Tenant.create!(name: "Salute Imóveis", slug: "salute-imoveis-#{SecureRandom.hex(3)}")
      admin_user = create(:admin_user, :admin, tenant: tenant)
      LayoutSetting.instance(tenant: tenant).update!(site_name: "Conexão Imobiliária", admin_primary_color: "#3E6F9E")
      LayoutSetting.instance(tenant: other_tenant).update!(site_name: "Salute Imóveis", admin_primary_color: "#DC2626")

      sign_in admin_user
      get "/admin/manifest.json"

      payload = JSON.parse(response.body)
      expect(response).to have_http_status(:ok)
      expect(payload["id"]).to eq("/admin?tenant=#{tenant.slug}")
      expect(payload["name"]).to eq("Conexão Imobiliária — Plataforma")
      expect(payload["theme_color"]).to eq("#3E6F9E")
      expect(payload["icons"].map { |i| i["src"] }).to all(include("tenant=#{tenant.slug}"))
      expect(payload.to_json).not_to include("Salute Imóveis", "#DC2626")
    end

    it "não exige autenticação" do
      get "/admin/manifest.json"

      expect(response).to have_http_status(:ok)
    end
  end
end
