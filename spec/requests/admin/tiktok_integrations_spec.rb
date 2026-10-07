require "rails_helper"

RSpec.describe "TikTok integration", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:admin) { create(:admin_user, :admin) }
  let(:integration) { TiktokIntegration.create!(tenant: admin.tenant, admin_user: admin, access_token: "token", ad_accounts: [{ "advertiser_id" => "123", "advertiser_name" => "Conta" }], selected_account_ids: ["123"], catalog: { "123" => { "name" => "Conta", "forms" => [{ "id" => "456", "name" => "Apartamento" }] } }) }
  before { host! "localhost"; sign_in admin }

  it "shows the connection using existing admin components" do
    integration
    get admin_tiktok_integration_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("TikTok Ads", "Salvar anunciantes", "Último lead recebido")
    expect(response.body).not_to include("private-token")
  end

  it "rejects unknown advertiser selection without changing this tenant" do
    integration
    patch admin_tiktok_integration_path, params: { tiktok_integration: { selected_account_ids: ["999"] } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(integration.reload.selected_account_ids).to eq(["123"])
  end

  it "does not exchange a code without valid OAuth state" do
    expect_any_instance_of(Tiktok::Client).not_to receive(:exchange_code)
    get callback_admin_tiktok_integration_path, params: { state: "forged", auth_code: "code" }
    expect(response).to redirect_to(admin_tiktok_integration_path)
  end

  it "protects the integration with existing permissions" do
    sign_out admin
    sign_in create(:admin_user)
    post connect_admin_tiktok_integration_path
    expect(response).to redirect_to(admin_root_path)
  end

  it "exchanges an authorized callback once and preserves the tenant identity" do
    allow(TiktokIntegration).to receive(:configured?).and_return(true)
    allow(Tiktok::GatewayClient).to receive(:register_oauth!)
    client = instance_double(Tiktok::Client)
    allow(Tiktok::Client).to receive(:new).and_return(client)
    state = nil
    allow(client).to receive(:authorization_url) do |**args|
      state = args.fetch(:state)
      "https://business-api.tiktok.com/portal/auth?state=#{state}"
    end
    expect(client).to receive(:exchange_code).with("valid-code").once.and_return({ "access_token" => "private-token" })
    allow(client).to receive(:accounts).and_return([{ "advertiser_id" => "123", "advertiser_name" => "Conta" }])
    post connect_admin_tiktok_integration_path
    get callback_admin_tiktok_integration_path, params: { state: state, auth_code: "valid-code" }
    expect(response).to redirect_to(admin_tiktok_integration_path)
    connected = TiktokIntegration.find_by!(tenant: admin.tenant)
    expect(connected.access_token).to eq("private-token")
    expect(connected.admin_user).to eq(admin)
    get callback_admin_tiktok_integration_path, params: { state: state, auth_code: "valid-code" }
    expect(flash[:alert]).to include("validar")
  end

  it "does not expose another tenant's advertisers" do
    other = create(:admin_user, :admin, tenant: Tenant.create!(name: "Outra", slug: "tiktok-private"))
    TiktokIntegration.create!(tenant: other.tenant, admin_user: other, access_token: "token", ad_accounts: [{ "advertiser_id" => "999", "advertiser_name" => "Conta privada" }])
    get admin_tiktok_integration_path
    expect(response.body).not_to include("Conta privada")
    post sync_admin_tiktok_integration_path
    expect(response).to have_http_status(:not_found)
  end

  it "stops local receiving and retains cleanup credentials if Gateway is unavailable" do
    integration
    allow(Tiktok::GatewayClient).to receive(:pause_unselected!).and_raise(Tiktok::Client::Error, "Gateway indisponível")
    delete disconnect_admin_tiktok_integration_path
    expect(integration.reload.selected_account_ids).to eq([])
    expect(integration.access_token).to eq("token")
    expect(integration.last_error).to eq("Gateway indisponível")
  end

  it "disconnects without removing previously received leads" do
    integration
    lead = create(:lead, tenant: admin.tenant, skip_automatic_routing: true)
    receipt = TiktokLeadReceipt.create!(tenant: admin.tenant, lead: lead, advertiser_id: "123", external_id: "keep")
    allow(Tiktok::GatewayClient).to receive(:pause_unselected!)
    client = instance_double(Tiktok::Client, subscriptions: [])
    allow(Tiktok::Client).to receive(:new).and_return(client)
    delete disconnect_admin_tiktok_integration_path
    expect(integration.reload).not_to be_connected
    expect(receipt.reload.lead).to eq(lead)
  end

  it "saves advertiser/form filters and rejects a foreign form" do
    integration
    post admin_distribution_rules_path, params: { distribution_rule: { name: "TikTok", source_tiktok: "1", tiktok_account_ids: ["", "123"], tiktok_form_ids: ["", "456"] } }
    rule = admin.tenant.distribution_rules.find_by!(name: "TikTok")
    expect(rule.tiktok_form_ids).to eq(["456"])
    patch admin_distribution_rule_path(rule), params: { distribution_rule: { tiktok_form_ids: ["999"] } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(rule.reload.tiktok_form_ids).to eq(["456"])
    get edit_admin_distribution_rule_path(rule)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Apartamento", "TikTok Ads")
  end
end
