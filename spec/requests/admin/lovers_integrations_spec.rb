require "rails_helper"

RSpec.describe "Admin::LoversIntegrations", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

  before do
    host! "localhost"
    sign_in admin
  end

  it "exibe a tela Lovers no menu de integrações" do
    get admin_lovers_integration_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Lovers")
    expect(response.body).to include("Token da API")
    expect(response.body).to include("Eventos de interação")
    expect(response.body).to include("EmailSequence/GetLeadsHistory")
  end

  it "salva configuração por conta sem expor token salvo" do
    other_tenant = Tenant.create!(name: "Lovers externo #{SecureRandom.hex(3)}", slug: "lovers-externo-#{SecureRandom.hex(4)}")

    patch admin_lovers_integration_path, params: {
      lovers: {
        enabled: "true",
        api_token: "token-lovers",
        default_origin: "Lovers",
        sync_start_date: "2026-09-01"
      }
    }

    expect(response).to redirect_to(admin_lovers_integration_path)
    expect(Setting.tenant_get(LoversIntegrationSetting::ENABLED_KEY, tenant: admin.tenant)).to eq("true")
    expect(Setting.tenant_get(LoversIntegrationSetting::API_TOKEN_KEY, tenant: admin.tenant)).to eq("token-lovers")
    expect(Setting.tenant_get(LoversIntegrationSetting::SYNC_START_DATE_KEY, tenant: admin.tenant)).to eq("2026-09-01")
    expect(Setting.tenant_get(LoversIntegrationSetting::ENABLED_KEY, tenant: other_tenant)).to be_nil

    get admin_lovers_integration_path
    expect(response.body).to include("Token salvo. Preencha apenas para substituir.")
    expect(response.body).not_to include("token-lovers")
  end

  it "sincroniza leads pela API Lovers" do
    Setting.set(LoversIntegrationSetting::ENABLED_KEY, "true", tenant: admin.tenant)
    Setting.set(LoversIntegrationSetting::API_TOKEN_KEY, "token-lovers", tenant: admin.tenant)
    agent = create(:admin_user, :field_agent, tenant: admin.tenant)
    rule = create(:distribution_rule, tenant: admin.tenant, source_site: false, source_lovers: true)
    create(:distribution_rule_agent, distribution_rule: rule, admin_user: agent)
    allow_any_instance_of(Lovers::Client).to receive(:leads).and_return(
      {
        "Data" => [
          { "Name" => "Cliente Lovers", "Email" => "cliente-lovers@example.test", "Phone" => "47 99999-3333" }
        ],
        "Links" => {}
      }
    )

    expect {
      post sync_now_admin_lovers_integration_path
    }.to change(Lead, :count).by(1)

    expect(response).to redirect_to(admin_lovers_integration_path)
    expect(Lead.last.origin).to eq("Lovers")
    expect(Lead.last.distribution_rule_id).to eq(rule.id)
    expect(Lead.last.admin_user_id).to eq(agent.id)
    expect(Setting.tenant_get(LoversIntegrationSetting::LAST_SYNC_STATUS_KEY, tenant: admin.tenant)).to eq("ok")
  end
end
