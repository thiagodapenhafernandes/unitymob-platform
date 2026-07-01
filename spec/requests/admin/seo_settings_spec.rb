require "rails_helper"

RSpec.describe "Admin::SeoSettings", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "seo-settings-#{SecureRandom.hex(8)}@salute.test") }
  let!(:seo_setting) do
    SeoSetting.create!(
      page_name: "imoveis:seo-settings-list",
      canonical_key: "imoveis:seo-settings-list",
      page_type: "property_listing",
      meta_title: "Buscar imóveis",
      meta_description: "Listagem pública de imóveis",
      canonical_path: "/imoveis",
      access_count: 10,
      seo_score: 88,
      active: true,
      apply_to_public: true,
      robots_index: true
    )
  end

  before do
    host! "localhost"
    sign_in admin
  end

  it "renderiza o inventário SEO com componentes operacionais" do
    get admin_seo_settings_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Páginas SEO")
    expect(response.body).to include("ax-workspace-heading")
    expect(response.body).to include("ax-metric-card")
    expect(response.body).to include("Páginas monitoradas")
    expect(response.body).to include("Busca de imóveis")
    expect(response.body).to include("Estratégia IA")
    expect(response.body).not_to include("Seo settings")
  end

  it "renderiza a edição com painéis operacionais e toggles compartilhados" do
    get edit_admin_seo_setting_path(seo_setting)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Identificação técnica")
    expect(response.body).to include("Snippet para buscadores")
    expect(response.body).to include("Controle público")
    expect(response.body).to include("ax-operational-panel")
    expect(response.body).to include("ax-toggle-chip")
    expect(response.body).to include("ax-sticky-action-footer")
    expect(response.body).not_to include("custom-checkbox-card")
  end
end
