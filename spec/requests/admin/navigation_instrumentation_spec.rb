require "rails_helper"

RSpec.describe "Admin navigation instrumentation", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

  before do
    host! "localhost"
    sign_in admin
  end

  it "mede renderização das páginas internas do admin e expõe o preloader global" do
    get admin_root_path

    expect(response).to have_http_status(:ok)
    expect(response.headers["X-Admin-Render-Duration-Ms"].to_f).to be > 0
    expect(response.headers["X-Admin-Page"]).to eq("admin/dashboard#index")
    expect(response.headers["Server-Timing"]).to include("admin_render;dur=")
    expect(response.body).to include('data-controller="ax-drawer admin-navigation"')
    expect(response.body).to include('data-admin-navigation-target="overlay"')
    expect(response.body).not_to include("ax-navbar__performance")
  end
end
