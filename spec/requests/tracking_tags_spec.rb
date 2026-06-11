require "rails_helper"

RSpec.describe "Tracking tags", type: :request do
  include Devise::Test::IntegrationHelpers

  before { host! "localhost" }

  it "renderiza Google Tag Manager e Pixel da Meta no site publico quando ativos" do
    Setting.set(TrackingIntegrationSetting::GTM_ENABLED_KEY, "true")
    Setting.set(TrackingIntegrationSetting::GTM_CONTAINER_ID_KEY, "GTM-ABC123")
    Setting.set(TrackingIntegrationSetting::META_PIXEL_ENABLED_KEY, "true")
    Setting.set(TrackingIntegrationSetting::META_PIXEL_ID_KEY, "123456789012345")

    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("https://www.googletagmanager.com/gtm.js?id=")
    expect(response.body).to include("https://www.googletagmanager.com/ns.html?id=GTM-ABC123")
    expect(response.body).to include("https://connect.facebook.net/en_US/fbevents.js")
    expect(response.body).to include("fbq('init', '123456789012345')")
    expect(response.body).to include("https://www.facebook.com/tr?id=123456789012345")
  end

  it "nao renderiza tags de trackeamento no painel administrativo" do
    admin = create(:admin_user, :admin)
    sign_in admin

    Setting.set(TrackingIntegrationSetting::GTM_ENABLED_KEY, "true")
    Setting.set(TrackingIntegrationSetting::GTM_CONTAINER_ID_KEY, "GTM-ABC123")
    Setting.set(TrackingIntegrationSetting::META_PIXEL_ENABLED_KEY, "true")
    Setting.set(TrackingIntegrationSetting::META_PIXEL_ID_KEY, "123456789012345")

    get admin_root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("googletagmanager.com/gtm.js")
    expect(response.body).not_to include("connect.facebook.net/en_US/fbevents.js")
  end
end
