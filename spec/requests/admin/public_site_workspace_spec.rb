require "rails_helper"

RSpec.describe "Admin public site workspace", type: :request do
  include Devise::Test::IntegrationHelpers

  before do
    host! "localhost"
    sign_in create(:admin_user, :admin)
  end

  it "padroniza as listagens de conteúdo público" do
    [admin_landing_pages_path, admin_banners_path, admin_home_sections_path, admin_seo_redirects_path].each do |path|
      get path
      expect(response).to have_http_status(:ok), path
      expect(response.body).to include("public-site-workspace"), path
      expect(response.body).to include("ax-workspace-heading"), path
    end
  end

  it "padroniza os editores estruturais e remove previews explicativos" do
    get edit_admin_home_setting_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("public-site-workspace")
    expect(response.body).not_to include("<strong>Dica:</strong>")

    get edit_admin_contact_setting_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("public-site-workspace")
    expect(response.body).not_to include("Preview dos Links")

    get edit_admin_footer_setting_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("public-site-workspace")
  end
end
