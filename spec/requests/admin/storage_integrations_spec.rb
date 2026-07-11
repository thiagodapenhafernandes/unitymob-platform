require "rails_helper"

RSpec.describe "Admin::StorageIntegrations", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

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
end
