require "rails_helper"

RSpec.describe "Admin::GoogleIntegrations", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }
  let(:service_account_json) do
    {
      type: "service_account",
      client_email: "calendar-sync@salute-crm-501321.iam.gserviceaccount.com",
      private_key: "-----BEGIN PRIVATE KEY-----\nFAKE\n-----END PRIVATE KEY-----\n"
    }.to_json
  end

  before do
    host! "localhost"
    sign_in admin
  end

  it "exibe a tela de Google Sheets no menu Google" do
    get admin_google_integration_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Google")
    expect(response.body).to include("Google Sheets")
    expect(response.body).to include("Agenda")
    expect(response.body).to include("Maps")
    expect(response.body).to include("Coluna-chave para atualização")
    expect(response.body).to include("Cód. imóvel CRM")
    expect(response.body).not_to include("Como esta integração será usada")
    expect(response.body).not_to include("Como a agenda será usada")
  end

  it "salva a configuração do Google Maps por conta" do
    patch admin_google_integration_path, params: {
      google_maps: {
        enabled: "true",
        api_key: "maps-key-restrita",
        default_display_mode: "approximate",
        approximate_radius_meters: "300",
        default_zoom: "16",
        satellite_enabled: "true",
        street_view_enabled: "false",
        external_link_enabled: "true"
      }
    }

    expect(response).to redirect_to(admin_google_integration_path(tab: "maps"))
    setting = GoogleMapsIntegrationSetting.find_by!(tenant: admin.tenant)
    expect(setting).to have_attributes(
      enabled: true,
      default_display_mode: "approximate",
      approximate_radius_meters: 300,
      default_zoom: 16,
      satellite_enabled: true,
      street_view_enabled: false,
      external_link_enabled: true
    )
    expect(setting.api_key).to eq("maps-key-restrita")
  end

  it "preserva a chave do Maps quando o campo vem em branco" do
    setting = GoogleMapsIntegrationSetting.for(admin.tenant)
    setting.update!(enabled: true, api_key: "maps-key-atual")

    patch admin_google_integration_path, params: {
      google_maps: {
        enabled: "true",
        api_key: "",
        default_display_mode: "exact",
        approximate_radius_meters: "220",
        default_zoom: "15",
        satellite_enabled: "true",
        street_view_enabled: "false",
        external_link_enabled: "true"
      }
    }

    expect(response).to redirect_to(admin_google_integration_path(tab: "maps"))
    expect(setting.reload.api_key).to eq("maps-key-atual")
    expect(setting.default_display_mode).to eq("exact")
  end

  it "renderiza a prévia somente para a configuração da conta atual" do
    setting = GoogleMapsIntegrationSetting.for(admin.tenant)
    setting.update!(enabled: true, api_key: "maps-key-preview")

    get admin_google_integration_path(tab: "maps")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Prévia da integração")
    expect(response.body).to include("maps-key-preview")
    expect(response.body).to include("data-public-property-map-provider-value=\"google\"")
  end

  it "salva as configuracoes de Apps Script para captacoes" do
    patch admin_google_integration_path, params: {
      google_sheets: {
        enabled: "true",
        web_app_url: "https://script.google.com/macros/s/abc/exec",
        token: "token-seguro",
        worksheet_name: "Captações",
        key_column: "Cód. imóvel CRM"
      }
    }

    expect(response).to redirect_to(admin_google_integration_path(tab: "sheets"))
    expect(Setting.get(GoogleSheetsIntegrationSetting::ENABLED_KEY, tenant: admin.tenant)).to eq("true")
    expect(Setting.get(GoogleSheetsIntegrationSetting::WEB_APP_URL_KEY, tenant: admin.tenant)).to eq("https://script.google.com/macros/s/abc/exec")
    expect(Setting.get(GoogleSheetsIntegrationSetting::TOKEN_KEY, tenant: admin.tenant)).to eq("token-seguro")
    expect(Setting.get(GoogleSheetsIntegrationSetting::WORKSHEET_NAME_KEY, tenant: admin.tenant)).to eq("Captações")
    expect(Setting.get(GoogleSheetsIntegrationSetting::KEY_COLUMN_KEY, tenant: admin.tenant)).to eq("Cód. imóvel CRM")
  end

  it "nao substitui o token salvo quando o campo vem em branco" do
    Setting.set(GoogleSheetsIntegrationSetting::TOKEN_KEY, "token-atual", tenant: admin.tenant)

    patch admin_google_integration_path, params: {
      google_sheets: {
        enabled: "true",
        web_app_url: "https://script.google.com/macros/s/abc/exec",
        token: "",
        worksheet_name: "Captações",
        key_column: "Cód. imóvel CRM"
      }
    }

    expect(response).to redirect_to(admin_google_integration_path(tab: "sheets"))
    expect(Setting.get(GoogleSheetsIntegrationSetting::TOKEN_KEY, tenant: admin.tenant)).to eq("token-atual")
  end

  it "exige url e token quando a integracao estiver ativa" do
    patch admin_google_integration_path, params: {
      google_sheets: {
        enabled: "true",
        web_app_url: "",
        token: "",
        worksheet_name: "Captações",
        key_column: "Cód. imóvel CRM"
      }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Revise os campos destacados antes de salvar")
    expect(Setting.get(GoogleSheetsIntegrationSetting::ENABLED_KEY, tenant: admin.tenant)).to be_nil
  end

  it "salva a configuracao da agenda Google da conta" do
    patch admin_google_integration_path, params: {
      google_calendar: {
        enabled: "true",
        calendar_id: "fotografias.saluteimoveis@gmail.com",
        default_duration_minutes: "60",
        service_account_json: service_account_json
      }
    }

    expect(response).to redirect_to(admin_google_integration_path(tab: "calendar"))

    setting = GoogleCalendarIntegrationSetting.find_by!(tenant: admin.tenant)
    expect(setting).to be_enabled
    expect(setting.calendar_id).to eq("fotografias.saluteimoveis@gmail.com")
    expect(setting.default_duration_minutes).to eq(60)
    expect(setting.service_account_credentials["client_email"]).to eq("calendar-sync@salute-crm-501321.iam.gserviceaccount.com")
  end

  it "nao substitui o JSON da service account quando o campo vem em branco" do
    setting = GoogleCalendarIntegrationSetting.for(admin.tenant)
    setting.update!(
      enabled: true,
      calendar_id: "fotografias.saluteimoveis@gmail.com",
      default_duration_minutes: 60,
      service_account_json: service_account_json
    )

    patch admin_google_integration_path, params: {
      google_calendar: {
        enabled: "true",
        calendar_id: "agenda-nova@salute.test",
        default_duration_minutes: "90",
        service_account_json: ""
      }
    }

    expect(response).to redirect_to(admin_google_integration_path(tab: "calendar"))
    setting.reload
    expect(setting.calendar_id).to eq("agenda-nova@salute.test")
    expect(setting.default_duration_minutes).to eq(90)
    expect(setting.service_account_credentials["client_email"]).to eq("calendar-sync@salute-crm-501321.iam.gserviceaccount.com")
  end

  it "cria evento de teste usando a agenda configurada" do
    setting = GoogleCalendarIntegrationSetting.for(admin.tenant)
    setting.update!(
      enabled: true,
      calendar_id: "fotografias.saluteimoveis@gmail.com",
      default_duration_minutes: 60,
      service_account_json: service_account_json
    )

    event = instance_double(Google::Apis::CalendarV3::Event, id: "evt_test")
    creator = instance_double(GoogleCalendar::TestEventCreator, call: event)
    allow(GoogleCalendar::TestEventCreator).to receive(:new).with(setting: setting, tenant: admin.tenant).and_return(creator)

    post test_calendar_admin_google_integration_path

    expect(response).to redirect_to(admin_google_integration_path(tab: "calendar"))
    follow_redirect!
    expect(response.body).to include("Evento de teste criado na Agenda Google: evt_test")
  end

  it "bloqueia usuario sem permissao de integracoes" do
    sign_out admin
    broker = create(:admin_user)
    sign_in broker

    get admin_google_integration_path

    expect(response).to redirect_to(admin_root_path)
  end
end
