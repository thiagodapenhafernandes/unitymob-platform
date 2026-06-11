require "rails_helper"

RSpec.describe "Admin::GoogleIntegrations", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

  before do
    host! "localhost"
    sign_in admin
  end

  it "exibe a tela de Google Sheets no menu Google" do
    get admin_google_integration_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Google")
    expect(response.body).to include("Google Sheets")
    expect(response.body).to include("Coluna-chave para atualização")
    expect(response.body).to include("Cód. imóvel CRM")
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

    expect(response).to redirect_to(admin_google_integration_path)
    expect(Setting.get(GoogleSheetsIntegrationSetting::ENABLED_KEY)).to eq("true")
    expect(Setting.get(GoogleSheetsIntegrationSetting::WEB_APP_URL_KEY)).to eq("https://script.google.com/macros/s/abc/exec")
    expect(Setting.get(GoogleSheetsIntegrationSetting::TOKEN_KEY)).to eq("token-seguro")
    expect(Setting.get(GoogleSheetsIntegrationSetting::WORKSHEET_NAME_KEY)).to eq("Captações")
    expect(Setting.get(GoogleSheetsIntegrationSetting::KEY_COLUMN_KEY)).to eq("Cód. imóvel CRM")
  end

  it "nao substitui o token salvo quando o campo vem em branco" do
    Setting.set(GoogleSheetsIntegrationSetting::TOKEN_KEY, "token-atual")

    patch admin_google_integration_path, params: {
      google_sheets: {
        enabled: "true",
        web_app_url: "https://script.google.com/macros/s/abc/exec",
        token: "",
        worksheet_name: "Captações",
        key_column: "Cód. imóvel CRM"
      }
    }

    expect(response).to redirect_to(admin_google_integration_path)
    expect(Setting.get(GoogleSheetsIntegrationSetting::TOKEN_KEY)).to eq("token-atual")
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
    expect(Setting.get(GoogleSheetsIntegrationSetting::ENABLED_KEY)).to be_nil
  end

  it "bloqueia usuario sem permissao de integracoes" do
    sign_out admin
    broker = create(:admin_user)
    sign_in broker

    get admin_google_integration_path

    expect(response).to redirect_to(admin_root_path)
  end
end
