require "rails_helper"

RSpec.describe "Admin::SeoDashboard", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "seo-dashboard-#{SecureRandom.hex(8)}@salute.test") }

  before do
    SeoSetting.create!(
      page_name: "imoveis:teste-dashboard-seo",
      canonical_key: "imoveis:teste-dashboard-seo",
      page_type: "property_listing",
      meta_title: "Imóveis para venda",
      meta_description: "Listagem pública de imóveis",
      canonical_path: "/imoveis",
      access_count: 12,
      seo_score: 92,
      active: true,
      apply_to_public: true,
      robots_index: true
    )

    host! "localhost"
    sign_in admin
  end

  it "renderiza o dashboard SEO com componentes operacionais" do
    get admin_seo_dashboard_path(period: "30")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Dashboard SEO")
    expect(response.body).to include("ax-workspace-heading")
    expect(response.body).to include("ax-metric-card")
    expect(response.body).to include("data-controller=\"seo-dashboard-charts\"")
    expect(response.body).to include("seoTrendChart")
    expect(response.body).to include("seoScoreChart")
    expect(response.body).to include("seoPageTypesChart")
    expect(response.body).to include("Busca de imóveis")
    expect(response.body).to include("Top 10 páginas mais acessadas")
    expect(response.body).to include("Correções com impacto")
  end
end
