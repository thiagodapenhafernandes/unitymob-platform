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
    integration.update!(enabled: true, status: "connected", access_token: "test-c2s-token", webhook_listening_enabled: true)
    previous_integration = integration.attributes
    other = Tenant.create!(name: "Outra conta", slug: "chaves-config-#{SecureRandom.hex(4)}")

    configure(account_code: "33380", integration_token: token, enabled: "1", tenant_id: other.id)

    expect(response).to redirect_to(admin_portal_integrations_path(portal: "chavesnamao", anchor: "portal-direct-leads"))
    connection = ChavesNaMaoConnection.find_by!(tenant: admin.tenant)
    expect(connection).to be_receiving
    expect(ChavesNaMaoConnection.where(tenant: other)).not_to exist
    expect(portal.reload.attributes).to eq(original)
    expect(integration.reload.attributes).to eq(previous_integration)
    expect(integration).to be_connected

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
    document = Nokogiri::HTML(response.body)
    expect(document.at_css('input[name="chaves_na_mao_connection[integration_token]"]')["value"]).to be_blank
    expect(document.at_css('#chaves_endpoint[data-clipboard-target="source"]')["value"]).to include(ChavesNaMaoConnection.find_by!(tenant: admin.tenant).route_key)
    expect(document.at_css('[data-action="clipboard#copy"]')).to be_present
    expect(response.body).to include("Aguardando validação de um lead de teste", "Salvar aqui não altera o C2S")
  end

  it "keeps independent credentials, URLs and receipts for each account" do
    configure(account_code: "33380", integration_token: token, enabled: "1")
    first = ChavesNaMaoConnection.find_by!(tenant: admin.tenant)
    first.chaves_na_mao_lead_receipts.create!(payload_digest: "first", payload: '{"id":"first"}', received_at: Time.current)
    other = Tenant.create!(name: "Outra conta", slug: "chaves-isolation-#{SecureRandom.hex(4)}")
    second_admin = create(:admin_user, :admin, tenant: other)
    sign_out admin
    sign_in second_admin
    configure(account_code: "444", integration_token: "y" * 64, enabled: "1")
    second = ChavesNaMaoConnection.find_by!(tenant: other)

    expect(second.route_key).not_to eq(first.route_key)
    expect(first.reload.integration_token).to eq(token)
    expect(second.integration_token).to eq("y" * 64)
    get admin_portal_integrations_path(portal: "chavesnamao")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(second.route_key)
    expect(response.body).not_to include(first.route_key, "Evento ##{first.chaves_na_mao_lead_receipts.sole.id}")
  end

  it "lets an unused disabled draft correct the account ID and locks it after receiving" do
    configure(account_code: "33380", integration_token: token, enabled: "0")
    connection = ChavesNaMaoConnection.find_by!(tenant: admin.tenant)
    configure(account_code: "444", enabled: "0")
    expect(connection.reload.account_code).to eq("444")
    configure(account_code: "444", enabled: "1")
    configure(account_code: "555", enabled: "0")
    expect(connection.reload.account_code).to eq("444")
    expect(connection).to be_enabled

    connection.update!(enabled: false)
    connection.chaves_na_mao_lead_receipts.create!(payload_digest: "received", payload: '{"id":"received"}', received_at: Time.current)
    configure(account_code: "555", enabled: "0")
    expect(connection.reload.account_code).to eq("444")
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
