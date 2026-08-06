require 'rails_helper'

RSpec.describe "Field::Manifests", type: :request do
  include Devise::Test::IntegrationHelpers

  describe "GET /field/manifest" do
    before do
      # Rails config.hosts whitelist não inclui www.example.com (default do Rack test).
      host! "localhost"
    end

    it "responde JSON com payload do PWA" do
      get "/field/manifest.json"
      expect(response).to have_http_status(:ok)
      payload = JSON.parse(response.body)
      expect(payload["id"]).to eq("/field?tenant=#{Tenant.public_for.slug}")
      expect(payload["name"]).to end_with(" — Campo")
      expect(payload["scope"]).to eq("/")
      expect(payload["start_url"]).to eq("/field?tenant=#{Tenant.public_for.slug}")
      expect(payload["display"]).to eq("standalone")
      expect(payload["icons"].map { |i| i["sizes"] }).to match_array(%w[192x192 512x512])
      expect(payload["icons"].map { |i| i["src"] }).to all(match(%r{\A/pwa-icon-(192|512)\?tenant=#{Tenant.public_for.slug}&v=\d+\z}))
      expect(response.headers["Cache-Control"]).to include("private")
      expect(response.headers["Vary"]).to include("Cookie")
    end

    it "usa o tenant do corretor autenticado no mesmo host" do
      tenant = Tenant.create!(name: "Conexão Imobiliária", slug: "conexao-imobiliaria-#{SecureRandom.hex(3)}")
      other_tenant = Tenant.create!(name: "Salute Imóveis", slug: "salute-imoveis-#{SecureRandom.hex(3)}")
      broker = create(:admin_user, :field_agent, tenant: tenant)
      LayoutSetting.instance(tenant: tenant).update!(site_name: "Conexão Imobiliária", admin_primary_color: "#3E6F9E")
      LayoutSetting.instance(tenant: other_tenant).update!(site_name: "Salute Imóveis", admin_primary_color: "#DC2626")

      sign_in broker
      get "/field/manifest.json"

      expect(response).to have_http_status(:ok)
      payload = JSON.parse(response.body)
      expect(payload["id"]).to eq("/field?tenant=#{tenant.slug}")
      expect(payload["name"]).to eq("Conexão Imobiliária — Campo")
      expect(payload["start_url"]).to eq("/field?tenant=#{tenant.slug}")
      expect(payload["theme_color"]).to eq("#3E6F9E")
      expect(payload["icons"].map { |i| i["src"] }).to all(include("tenant=#{tenant.slug}"))
      expect(payload.to_json).not_to include("Salute Imóveis", "#DC2626")
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
