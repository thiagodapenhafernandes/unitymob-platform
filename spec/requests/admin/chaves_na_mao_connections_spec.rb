require "rails_helper"

RSpec.describe "Chaves na Mão account configuration", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:admin) { create(:admin_user, :admin) }
  let(:token) { "validation-token-#{'x' * 40}" }

  before do
    host! "localhost"
    sign_in admin
  end

  def configure(attributes)
    patch admin_chaves_na_mao_connection_path, params: { chaves_na_mao_connection: attributes }
  end

  it "configures only the current account and preserves the feed and C2S settings" do
    portal = PortalIntegration.for_portal!("chavesnamao", tenant: admin.tenant)
    original = portal.attributes
    integration = ExternalLeadIntegration.find_or_create_by!(tenant: admin.tenant)
    previous_integration = integration.attributes
    other = Tenant.create!(name: "Outra conta", slug: "chaves-config-#{SecureRandom.hex(4)}")

    configure(account_code: "33380", integration_token: token, enabled: "1", tenant_id: other.id)

    expect(response).to redirect_to(admin_portal_integrations_path(portal: "chavesnamao", anchor: "portal-direct-leads"))
    connection = ChavesNaMaoConnection.find_by!(tenant: admin.tenant)
    expect(connection).to be_receiving
    expect(ChavesNaMaoConnection.where(tenant: other)).not_to exist
    expect(portal.reload.attributes).to eq(original)
    expect(integration.reload.attributes).to eq(previous_integration)

    configure(account_code: "33380", integration_token: "", enabled: "0")
    expect(connection.reload.integration_token).to eq(token)
    expect(connection).not_to be_receiving
  end

  it "shows validation status, a separate URL and no credential value" do
    configure(account_code: "33380", integration_token: token, enabled: "1")
    get admin_portal_integrations_path(portal: "chavesnamao")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Receber eventos para validação", "Em validação", "/webhooks/chaves_na_mao/")
    expect(response.body).not_to include(token)
    expect(Nokogiri::HTML(response.body).at_css('input[name="chaves_na_mao_connection[integration_token]"]')["value"]).to be_blank
  end

  it "rejects enabling without credentials" do
    configure(account_code: "33380", enabled: "1")
    expect(ChavesNaMaoConnection.where(tenant: admin.tenant)).not_to exist
  end

  it "requires integration management permission" do
    sign_out admin
    sign_in create(:admin_user)
    configure(account_code: "33380", integration_token: token, enabled: "1")
    expect(ChavesNaMaoConnection.count).to eq(0)
    expect(response).not_to have_http_status(:ok)
  end
end
