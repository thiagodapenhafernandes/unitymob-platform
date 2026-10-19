require "rails_helper"

RSpec.describe "Conexão operacional de leitura GA4", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:admin) { create(:admin_user, :admin) }
  let(:credentials) do
    { type: "service_account", client_email: "reader@project.iam.gserviceaccount.com",
      private_key: OpenSSL::PKey::RSA.new(2048).to_pem, token_uri: "https://oauth2.googleapis.com/token" }.to_json
  end
  before { host! "localhost"; sign_in admin }

  it "disponibiliza Analytics em Integrações por conta sem criar ou ativar ao abrir" do
    expect { get admin_google_integration_path(tab: "ga4") }.not_to change(Ga4ConversionConfig, :count)
    expect(response.body).to include("Relatórios do GA4", "ID numérico da propriedade")
    expect(response.body).to include('name="ga4[reporting_enabled]"')
  end

  it "salva credencial cifrada sem alterar o envio existente e sem reexibi-la" do
    config = Ga4ConversionConfig.create!(tenant: admin.tenant, enabled: true, activated_at: 1.day.ago, measurement_id: "G-EXISTING", api_secret: "existing-send-secret")
    patch admin_google_integration_path, params: { ga4: { reporting_enabled: "true", reporting_property_id: "123456", reporting_credentials: credentials, api_secret: "injected", tenant_id: 9999 } }
    expect(response).to redirect_to(admin_google_integration_path(tab: "ga4"))
    config.reload
    expect(config.reporting_configured?).to be(true)
    expect(config.api_secret).to eq("existing-send-secret")
    raw = ActiveRecord::Base.connection.select_value("SELECT reporting_credentials FROM ga4_conversion_configs WHERE id = #{config.id}")
    expect(raw).not_to include("BEGIN RSA PRIVATE KEY")
    get admin_google_integration_path(tab: "ga4")
    expect(response.body).not_to include("BEGIN RSA PRIVATE KEY", "reader@project", "existing-send-secret")
    patch admin_google_integration_path, params: { ga4: { reporting_enabled: "false", reporting_credentials: "" } }
    expect(response).to have_http_status(:redirect)
    expect(config.reload.reporting_enabled?).to be(false)
    expect(config.reporting_credentials).to eq(credentials)
    expect(config.enabled?).to be(true)
  end

  it "rejeita endpoints arbitrários no JSON e não exibe a credencial em erro" do
    invalid = JSON.parse(credentials).merge("token_uri" => "http://internal.example/token").to_json
    patch admin_google_integration_path, params: { ga4: { reporting_enabled: "true", reporting_property_id: "123456", reporting_credentials: invalid } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).not_to include("BEGIN RSA PRIVATE KEY", "internal.example")
    expect(Ga4ConversionConfig.where(tenant: admin.tenant)).not_to exist
  end

  it "mantém outra conta sem alteração e impede usuário sem permissão" do
    other = Tenant.create!(name: "Salute preservada", slug: "ga4-salute-#{SecureRandom.hex(4)}")
    untouched = Ga4ConversionConfig.create!(tenant: other)
    patch admin_google_integration_path, params: { ga4: { reporting_enabled: "false", reporting_property_id: "" } }
    expect(untouched.reload.reporting_enabled?).to be(false)
    expect(untouched.reporting_property_id).to be_nil
    sign_out admin
    sign_in create(:admin_user, tenant: admin.tenant)
    expect { patch admin_google_integration_path, params: { ga4: { reporting_enabled: "false" } } }.not_to change { Ga4ConversionConfig.find_by(tenant: admin.tenant)&.updated_at }
    expect(response).not_to have_http_status(:ok)
  end
end
