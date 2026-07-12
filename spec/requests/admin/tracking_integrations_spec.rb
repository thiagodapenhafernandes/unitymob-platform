require "rails_helper"

RSpec.describe "Admin::TrackingIntegrations", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

  before do
    host! "localhost"
    sign_in admin
  end

  it "exibe as abas de Google Tag Manager e Pixel da Meta" do
    get admin_tracking_integration_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Rastreamento")
    expect(response.body).to include("Google Tag Manager")
    expect(response.body).to include("Pixel da Meta")
    expect(response.body).to include("GTM-XXXXXXX")
    expect(response.body).to include("tracking-workspace__layout")
    expect(response.body).to include("tracking-tab-panel")
    expect(response.body).not_to include('class="tab-pane')
    expect(response.body).not_to include("Onde a tag é instalada")
  end

  it "salva as configuracoes de trackeamento" do
    patch admin_tracking_integration_path, params: {
      tab: "meta_pixel",
      tracking: {
        google_tag_manager_enabled: "true",
        google_tag_manager_container_id: "gtm-abc123",
        meta_pixel_enabled: "true",
        meta_pixel_id: "123456789012345"
      }
    }

    expect(response).to redirect_to(admin_tracking_integration_path(tab: "meta_pixel"))
    expect(Setting.get(TrackingIntegrationSetting::GTM_ENABLED_KEY, tenant: admin.tenant)).to eq("true")
    expect(Setting.get(TrackingIntegrationSetting::GTM_CONTAINER_ID_KEY, tenant: admin.tenant)).to eq("GTM-ABC123")
    expect(Setting.get(TrackingIntegrationSetting::META_PIXEL_ENABLED_KEY, tenant: admin.tenant)).to eq("true")
    expect(Setting.get(TrackingIntegrationSetting::META_PIXEL_ID_KEY, tenant: admin.tenant)).to eq("123456789012345")
  end

  it "valida IDs antes de salvar" do
    patch admin_tracking_integration_path, params: {
      tracking: {
        google_tag_manager_enabled: "true",
        google_tag_manager_container_id: "container livre",
        meta_pixel_enabled: "true",
        meta_pixel_id: "abc"
      }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("ID do container GTM deve seguir o formato GTM-XXXXXXX")
    expect(response.body).to include("ID do Pixel da Meta não pode ficar em branco")
  end

  it "isola o rastreamento por conta" do
    patch admin_tracking_integration_path, params: {
      tracking: { google_tag_manager_enabled: "true", google_tag_manager_container_id: "GTM-CONTA1", meta_pixel_enabled: "false" }
    }
    other_tenant = Tenant.create!(name: "Outra conta", slug: "outra-conta-#{SecureRandom.hex(3)}")
    other_admin = create(:admin_user, :admin, tenant: other_tenant)
    sign_out admin
    sign_in other_admin

    get admin_tracking_integration_path

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("GTM-CONTA1")
    expect(Setting.get(TrackingIntegrationSetting::GTM_CONTAINER_ID_KEY, "", tenant: other_tenant)).to eq("")
  end
end
