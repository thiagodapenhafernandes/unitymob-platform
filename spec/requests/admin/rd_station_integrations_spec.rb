require "rails_helper"

RSpec.describe "Admin::RdStationIntegrations", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

  before do
    host! "localhost"
    sign_in admin
  end

  it "exibe a tela RD Station no menu de integrações" do
    get admin_rd_station_integration_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("RD Station")
    expect(response.body).to include("Receber leads da RD Station automaticamente")
    expect(response.body).to include("Client ID")
    expect(response.body).to include("URL de callback OAuth")
    expect(response.body).to include("URL do webhook de leads")
    expect(response.body).to include("Instruções do webhook")
    expect(response.body).to include("Conectar RD Station")
    expect(response.body).not_to include("Segredo do webhook")
  end

  it "gera a URL do webhook ao abrir a tela" do
    expect {
      get admin_rd_station_integration_path
    }.to change { Setting.tenant_get(RdStationIntegrationSetting::WEBHOOK_SECRET_KEY, tenant: admin.tenant).present? }.from(false).to(true)

    secret = Setting.tenant_get(RdStationIntegrationSetting::WEBHOOK_SECRET_KEY, tenant: admin.tenant)
    expect(response.body).to include("http://localhost/admin/rd_station_integration/callback")
    expect(response.body).to include("http://localhost/webhooks/rd_station/#{secret}")
  end

  it "mostra a URL do webhook da conta quando o segredo foi salvo" do
    Setting.set(RdStationIntegrationSetting::WEBHOOK_SECRET_KEY, "segredo-salute", tenant: admin.tenant)

    get admin_rd_station_integration_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Webhook RD Station")
    expect(response.body).to include("http://localhost/webhooks/rd_station/segredo-salute")
    expect(response.body).to include("Unitymob - Leads RD Station")
  end

  it "salva a configuração por conta" do
    other_tenant = Tenant.create!(name: "RD externo #{SecureRandom.hex(3)}", slug: "rd-externo-#{SecureRandom.hex(4)}")

    patch admin_rd_station_integration_path, params: {
      rd_station: {
        enabled: "true",
        client_id: "client-id",
        client_secret: "client-secret",
        default_business_type: "locacao",
        default_origin: "RD Station"
      }
    }

    expect(response).to redirect_to(admin_rd_station_integration_path)
    expect(Setting.tenant_get(RdStationIntegrationSetting::ENABLED_KEY, tenant: admin.tenant)).to eq("true")
    expect(Setting.tenant_get(RdStationIntegrationSetting::CLIENT_ID_KEY, tenant: admin.tenant)).to eq("client-id")
    expect(Setting.tenant_get(RdStationIntegrationSetting::CLIENT_SECRET_KEY, tenant: admin.tenant)).to eq("client-secret")
    expect(Setting.tenant_get(RdStationIntegrationSetting::WEBHOOK_SECRET_KEY, tenant: admin.tenant)).to be_present
    expect(Setting.tenant_get(RdStationIntegrationSetting::DEFAULT_BUSINESS_TYPE_KEY, tenant: admin.tenant)).to eq("locacao")
    expect(Setting.tenant_get(RdStationIntegrationSetting::ENABLED_KEY, tenant: other_tenant)).to be_nil
  end

  it "gera o segredo do webhook automaticamente ao salvar pela primeira vez" do
    patch admin_rd_station_integration_path, params: {
      rd_station: {
        enabled: "false",
        client_id: "client-id",
        client_secret: "client-secret",
        default_business_type: "auto",
        default_origin: "RD Station"
      }
    }

    expect(response).to redirect_to(admin_rd_station_integration_path)
    expect(Setting.tenant_get(RdStationIntegrationSetting::WEBHOOK_SECRET_KEY, tenant: admin.tenant)).to be_present
  end

  it "não substitui credenciais sensíveis salvas quando os campos vêm em branco" do
    Setting.set(RdStationIntegrationSetting::CLIENT_SECRET_KEY, "client-secret-atual", tenant: admin.tenant)
    Setting.set(RdStationIntegrationSetting::WEBHOOK_SECRET_KEY, "secret-atual", tenant: admin.tenant)

    patch admin_rd_station_integration_path, params: {
      rd_station: {
        enabled: "true",
        client_id: "client-id",
        client_secret: "",
        default_business_type: "auto",
        default_origin: "RD Station"
      }
    }

    expect(response).to redirect_to(admin_rd_station_integration_path)
    expect(Setting.tenant_get(RdStationIntegrationSetting::CLIENT_SECRET_KEY, tenant: admin.tenant)).to eq("client-secret-atual")
    expect(Setting.tenant_get(RdStationIntegrationSetting::WEBHOOK_SECRET_KEY, tenant: admin.tenant)).to eq("secret-atual")
  end

  it "conecta via OAuth e salva os tokens retornados pela RD" do
    Setting.set(RdStationIntegrationSetting::CLIENT_ID_KEY, "client-id", tenant: admin.tenant)
    Setting.set(RdStationIntegrationSetting::CLIENT_SECRET_KEY, "client-secret", tenant: admin.tenant)

    captured_state = nil
    allow_any_instance_of(RdStation::Client).to receive(:authorization_url) do |_client, redirect_uri:, state:|
      captured_state = state
      "https://api.rd.services/auth/dialog?client_id=client-id&state=#{state}"
    end
    get connect_admin_rd_station_integration_path

    expect(response).to redirect_to("https://api.rd.services/auth/dialog?client_id=client-id&state=#{captured_state}")

    allow_any_instance_of(RdStation::Client).to receive(:exchange_code!).and_return(
      "access_token" => "access-rd",
      "refresh_token" => "refresh-rd",
      "expires_in" => 86_400
    )

    get callback_admin_rd_station_integration_path, params: {
      code: "oauth-code",
      state: captured_state
    }

    expect(response).to redirect_to(admin_rd_station_integration_path)
    expect(Setting.tenant_get(RdStationIntegrationSetting::API_TOKEN_KEY, tenant: admin.tenant)).to eq("access-rd")
    expect(Setting.tenant_get(RdStationIntegrationSetting::REFRESH_TOKEN_KEY, tenant: admin.tenant)).to eq("refresh-rd")
  end
end
