require "rails_helper"

RSpec.describe "Admin::LoftIntegrations", type: :request do
  include Devise::Test::IntegrationHelpers

  before do
    host! "localhost"
    sign_in create(:admin_user, :admin)
  end

  it "exibe configuração, comandos e monitoramento no workspace" do
    get admin_loft_integrations_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Integração Vista Soft")
    expect(response.body).to include("loft-workspace__layout")
    expect(response.body).to include("Preservar campos editados manualmente")
    expect(response.body).to include("Comandos de sincronização")
    expect(response.body).to include("loft_status_panel")
  end

  it "mantém explícita a configuração de preservação de campos manuais" do
    patch admin_loft_integrations_path, params: {
      loft: {
        enabled: "false",
        preserve_manual_fields: "true",
        sync_batch_size: "100",
        images_sync_limit: "100",
        poll_processing_interval_ms: "2000",
        poll_idle_interval_ms: "6000",
        poll_slow_interval_ms: "15000"
      }
    }

    expect(response).to redirect_to(admin_loft_integrations_path)
    expect(Setting.get("loft_preserve_manual_fields", tenant: Tenant.default)).to eq("true")
  end
end
