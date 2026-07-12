require "rails_helper"

RSpec.describe "Admin::StorageIntegrations", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, super_admin: true) }

  before do
    host! "localhost"
    sign_in admin
  end

  it "renderiza o workspace usando as métricas reais de armazenamento" do
    get admin_storage_integration_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Armazenamento")
    expect(response.body).to include("anexos")
    expect(response.body).to include("blobs")
    expect(response.body).to include("Fotos públicas/CDN")
  end

  it "bloqueia admin de conta porque a configuração de storage é global" do
    sign_out admin
    sign_in create(:admin_user, :admin)

    get admin_storage_integration_path

    expect(response).to redirect_to(admin_root_path)
  end
end
