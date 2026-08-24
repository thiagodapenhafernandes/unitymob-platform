require "rails_helper"

RSpec.describe "Tracking tags", type: :request do
  include Devise::Test::IntegrationHelpers

  before { host! "localhost" }

  it "renderiza Google Tag Manager e Pixel da Meta no site publico quando ativos" do
    Setting.set(TrackingIntegrationSetting::GTM_ENABLED_KEY, "true")
    Setting.set(TrackingIntegrationSetting::GTM_CONTAINER_ID_KEY, "GTM-ABC123")
    Setting.set(TrackingIntegrationSetting::META_PIXEL_ENABLED_KEY, "true")
    Setting.set(TrackingIntegrationSetting::META_PIXEL_ID_KEY, "123456789012345")
    Setting.set(TrackingIntegrationSetting::GOOGLE_ADS_ENABLED_KEY, "true")
    Setting.set(TrackingIntegrationSetting::GOOGLE_ADS_CONVERSION_ID_KEY, "AW-16492801046")
    Setting.set(TrackingIntegrationSetting::GOOGLE_SITE_VERIFICATION_TOKEN_KEY, "google_token-123")
    Setting.set(TrackingIntegrationSetting::RD_STATION_ENABLED_KEY, "true")
    Setting.set(TrackingIntegrationSetting::RD_STATION_LOADER_URL_KEY, "https://d335luupugsy2.cloudfront.net/js/loader-scripts/df2d21d0-47b3-4eeb-bf1d-e3a1c2c03b67-loader.js")

    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('meta name="google-site-verification" content="google_token-123"')
    expect(response.body).to include("https://www.googletagmanager.com/gtm.js?id=")
    expect(response.body).to include("https://www.googletagmanager.com/gtag/js?id=AW-16492801046")
    expect(response.body).to include('w.gtag("config", "AW-16492801046")')
    expect(response.body).to include("https://connect.facebook.net/en_US/fbevents.js")
    expect(response.body).to include('w.fbq("init", "123456789012345")')
    expect(response.body).to include("https://d335luupugsy2.cloudfront.net/js/loader-scripts/df2d21d0-47b3-4eeb-bf1d-e3a1c2c03b67-loader.js")
  end

  it "nao renderiza tags de trackeamento no painel administrativo" do
    admin = create(:admin_user, :admin)
    sign_in admin

    Setting.set(TrackingIntegrationSetting::GTM_ENABLED_KEY, "true")
    Setting.set(TrackingIntegrationSetting::GTM_CONTAINER_ID_KEY, "GTM-ABC123")
    Setting.set(TrackingIntegrationSetting::META_PIXEL_ENABLED_KEY, "true")
    Setting.set(TrackingIntegrationSetting::META_PIXEL_ID_KEY, "123456789012345")
    Setting.set(TrackingIntegrationSetting::GOOGLE_ADS_ENABLED_KEY, "true")
    Setting.set(TrackingIntegrationSetting::GOOGLE_ADS_CONVERSION_ID_KEY, "AW-16492801046")
    Setting.set(TrackingIntegrationSetting::GOOGLE_SITE_VERIFICATION_TOKEN_KEY, "google_token-123")
    Setting.set(TrackingIntegrationSetting::RD_STATION_ENABLED_KEY, "true")
    Setting.set(TrackingIntegrationSetting::RD_STATION_LOADER_URL_KEY, "https://d335luupugsy2.cloudfront.net/js/loader-scripts/df2d21d0-47b3-4eeb-bf1d-e3a1c2c03b67-loader.js")

    get admin_root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("googletagmanager.com/gtm.js")
    expect(response.body).not_to include("googletagmanager.com/gtag/js")
    expect(response.body).not_to include("connect.facebook.net/en_US/fbevents.js")
    expect(response.body).not_to include("google-site-verification")
    expect(response.body).not_to include("d335luupugsy2.cloudfront.net")
  end
end
