require "rails_helper"

RSpec.describe "Admin::TrackingIntegrations", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

  before do
    host! "localhost"
    sign_in admin
  end

  it "exibe as abas de rastreamento" do
    get admin_tracking_integration_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Rastreamento")
    expect(response.body).to include("Google Tag Manager")
    expect(response.body).to include("Pixel da Meta")
    expect(response.body).to include("Google Ads")
    expect(response.body).to include("Outros rastreadores")
    expect(response.body).to include("GTM-XXXXXXX")
    expect(response.body).to include("AW-000000000")
    expect(response.body).to include("Google Search Console")
    expect(response.body).to include("URL do loader RD Station")
    expect(response.body).to include("tracking-workspace__layout")
    expect(response.body).to include("tracking-tab-panel")
    document = Nokogiri::HTML(response.body)
    expect(document.at_css('input[name="tracking[google_tag_manager_enabled]"][role="switch"]')).to be_present
    expect(document.at_css('input[name="tracking[meta_pixel_enabled]"][role="switch"]')).to be_present
    expect(document.at_css('input[name="tracking[google_ads_enabled]"][role="switch"]')).to be_present
    expect(document.at_css('input[name="tracking[rd_station_enabled]"][role="switch"]')).to be_present
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
        meta_pixel_id: "123456789012345",
        google_ads_enabled: "true",
        google_ads_conversion_id: "aw-16492801046",
        google_site_verification_token: "0ZknXKrUXoTutQ0OvvF4ijmFP4Aw5JnuJGq0eY8KPjY",
        rd_station_enabled: "true",
        rd_station_loader_url: "https://d335luupugsy2.cloudfront.net/js/loader-scripts/df2d21d0-47b3-4eeb-bf1d-e3a1c2c03b67-loader.js"
      }
    }

    expect(response).to redirect_to(admin_tracking_integration_path(tab: "meta_pixel"))
    expect(Setting.get(TrackingIntegrationSetting::GTM_ENABLED_KEY, tenant: admin.tenant)).to eq("true")
    expect(Setting.get(TrackingIntegrationSetting::GTM_CONTAINER_ID_KEY, tenant: admin.tenant)).to eq("GTM-ABC123")
    expect(Setting.get(TrackingIntegrationSetting::META_PIXEL_ENABLED_KEY, tenant: admin.tenant)).to eq("true")
    expect(Setting.get(TrackingIntegrationSetting::META_PIXEL_ID_KEY, tenant: admin.tenant)).to eq("123456789012345")
    expect(Setting.get(TrackingIntegrationSetting::GOOGLE_ADS_ENABLED_KEY, tenant: admin.tenant)).to eq("true")
    expect(Setting.get(TrackingIntegrationSetting::GOOGLE_ADS_CONVERSION_ID_KEY, tenant: admin.tenant)).to eq("AW-16492801046")
    expect(Setting.get(TrackingIntegrationSetting::GOOGLE_SITE_VERIFICATION_TOKEN_KEY, tenant: admin.tenant)).to eq("0ZknXKrUXoTutQ0OvvF4ijmFP4Aw5JnuJGq0eY8KPjY")
    expect(Setting.get(TrackingIntegrationSetting::RD_STATION_ENABLED_KEY, tenant: admin.tenant)).to eq("true")
    expect(Setting.get(TrackingIntegrationSetting::RD_STATION_LOADER_URL_KEY, tenant: admin.tenant)).to eq("https://d335luupugsy2.cloudfront.net/js/loader-scripts/df2d21d0-47b3-4eeb-bf1d-e3a1c2c03b67-loader.js")
  end

  it "valida IDs antes de salvar" do
    patch admin_tracking_integration_path, params: {
      tracking: {
        google_tag_manager_enabled: "true",
        google_tag_manager_container_id: "container livre",
        meta_pixel_enabled: "true",
        meta_pixel_id: "abc",
        google_ads_enabled: "true",
        google_ads_conversion_id: "123",
        google_site_verification_token: "<script>",
        rd_station_enabled: "true",
        rd_station_loader_url: "https://example.com/tracker.js"
      }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("ID do container GTM deve seguir o formato GTM-XXXXXXX")
    expect(response.body).to include("ID do Pixel da Meta não pode ficar em branco")
    expect(response.body).to include("ID de conversão do Google Ads deve seguir o formato AW-000000000")
    expect(response.body).to include("Token de verificação do Google deve conter apenas letras, números, hífen ou underline")
    expect(response.body).to include("URL do loader RD Station deve ser uma URL oficial do loader RD Station")
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
