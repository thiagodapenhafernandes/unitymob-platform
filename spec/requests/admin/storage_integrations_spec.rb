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
    progress = Nokogiri::HTML(response.body).at_css("progress.ax-progress__bar[data-storage-public-photo-publish-target='bar']")
    expect(progress).to be_present
    expect(progress["style"]).to be_nil
    expect(progress["max"]).to eq("100")
  end

  it "isola a configuração de armazenamento por conta" do
    own_setting = StorageIntegrationSetting.current(tenant: admin.tenant)
    own_setting.update!(public_photos_enabled: false)
    other_tenant = Tenant.create!(name: "Outro storage", slug: "outro-storage-#{SecureRandom.hex(3)}")
    other_admin = create(:admin_user, :admin, tenant: other_tenant)
    sign_out admin
    sign_in other_admin

    get admin_storage_integration_path

    expect(response).to have_http_status(:ok)
    expect(StorageIntegrationSetting.current(tenant: other_tenant).public_photos_enabled?).to be(true)
    expect(StorageIntegrationSetting.where(tenant: [admin.tenant, other_tenant]).count).to eq(2)
  end
end
