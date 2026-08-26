require "rails_helper"

RSpec.describe "Admin::ExternalLeadIntegrations", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

  before do
    host! "localhost"
    sign_in admin
  end

  it "exibe a tela dedicada de migração de leads em Integrações" do
    get admin_external_lead_integration_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Migração de Leads")
    expect(response.body).to include("Conexão da conta externa")
    expect(response.body).to include("Importar histórico")
    expect(response.body).to include("Etapas de Lead usadas na migração")
    expect(response.body).to include("Regra de apoio")
    expect(response.body).not_to include("C2S")
    document = Nokogiri::HTML(response.body)
    expect(document.css("button.lead-migration-command").size).to eq(2)
    expect(document.at_css("input#external_lead_integration_webhook_listening_enabled")).to be_present
    expect(response.body).to include("Escutar novos leads automaticamente")
    expect(document.at_css(".lead-migration-webhook-list")).to be_present
  end

  it "exibe integração conectada com regra, vendedores e leads importados" do
    broker = create(:admin_user, tenant: admin.tenant, name: "Corretor Espelhado", email: "espelhado@example.test")
    owner = create(:admin_user, :admin, tenant: admin.tenant, name: "Dono da Conta", email: "owner-lead-migration-view@example.test")
    rule = create(:distribution_rule, tenant: admin.tenant, name: ExternalLeadIntegration::SUPPORT_RULE_NAME)
    integration = create(
      :external_lead_integration,
      tenant: admin.tenant,
      distribution_rule: rule,
      sellers_payload: [
        { "id" => "seller-1", "name" => "Vendedor Externo", "email" => broker.email },
        { "id" => "seller-owner", "name" => "Dono Externo", "email" => owner.email }
      ],
      seller_mappings: { "seller-1" => broker.id, "seller-owner" => owner.id }
    )
    create(:lead, tenant: admin.tenant, external_lead_integration: integration, external_lead_id: "lead-lead-migration-1", name: "Lead Migrado", origin: ExternalLeadIntegration::LEAD_ORIGIN, external_last_synced_at: Time.current)

    get admin_external_lead_integration_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Corretor Espelhado")
    expect(response.body).to include("Fora da roleta")
    expect(response.body).to include("Lead Migrado")
    expect(response.body).to include(webhooks_external_lead_path(integration.webhook_token))
    expect(response.body).to include(ExternalLeadIntegration::SUPPORT_RULE_NAME)
  end

  it "exibe o webhook com o dominio canônico de app do tenant" do
    admin.tenant.tenant_domains.create!(hostname: "conexaobc.com", primary_domain: true)
    admin.tenant.tenant_domains.create!(hostname: "app.conexaobc.com")
    integration = create(:external_lead_integration, tenant: admin.tenant)

    get admin_external_lead_integration_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("https://app.conexaobc.com/webhooks/external_leads/#{integration.webhook_token}")
  end

  it "salva token e executa setup da integração" do
    service = instance_double(ExternalLeadMigration::SetupService, call: true)
    allow(ExternalLeadMigration::SetupService).to receive(:call) do |integration:|
      integration.update!(
        enabled: true,
        status: "connected",
        company_name: "Conta externa teste",
        sync_message: "Conexão externa validada."
      )
      service.call
    end

    patch admin_external_lead_integration_path, params: {
      external_lead_integration: {
        enabled: "1",
        access_token: "token-externo"
      }
    }

    expect(response).to redirect_to(admin_external_lead_integration_path)
    integration = ExternalLeadIntegration.current(admin.tenant)
    expect(integration).to be_persisted
    expect(integration.access_token).to eq("token-externo")
    expect(integration.connected_by_admin_user).to eq(admin)
    expect(ExternalLeadMigration::SetupService).to have_received(:call).with(integration:)
  end

  it "habilita escuta de novos leads ao salvar com checkbox marcado" do
    admin.tenant.tenant_domains.create!(hostname: "conexaobc.com", primary_domain: true)
    admin.tenant.tenant_domains.create!(hostname: "app.conexaobc.com")
    allow(ExternalLeadMigration::SetupService).to receive(:call) do |integration:|
      integration.update!(
        enabled: true,
        status: "connected",
        company_name: "Conta externa teste",
        sync_message: "Conexão externa validada."
      )
    end
    allow(ExternalLeadMigration::WebhookSubscriptionService).to receive(:subscribe!) do |integration:, hook_url:|
      integration.update!(
        webhook_listening_enabled: true,
        webhook_url: hook_url,
        subscribed_at: Time.current,
        unsubscribed_at: nil
      )
    end

    patch admin_external_lead_integration_path, params: {
      external_lead_integration: {
        enabled: "1",
        webhook_listening_enabled: "1",
        access_token: "token-externo"
      }
    }

    integration = ExternalLeadIntegration.current(admin.tenant)
    expect(response).to redirect_to(admin_external_lead_integration_path)
    expect(integration.reload.webhook_listening_enabled?).to be(true)
    expect(integration.subscribed_at).to be_present
    expect(ExternalLeadMigration::WebhookSubscriptionService).to have_received(:subscribe!).with(
      integration:,
      hook_url: "https://app.conexaobc.com/webhooks/external_leads/#{integration.webhook_token}"
    )
  end

  it "desabilita escuta de novos leads sem inativar a integração" do
    integration = create(
      :external_lead_integration,
      tenant: admin.tenant,
      webhook_listening_enabled: true,
      subscribed_at: 1.hour.ago,
      webhook_url: "https://example.test/webhooks/external_leads/token"
    )
    allow(ExternalLeadMigration::SetupService).to receive(:call) do |integration:|
      integration.update!(enabled: true, status: "connected")
    end
    allow(ExternalLeadMigration::WebhookSubscriptionService).to receive(:unsubscribe!) do |integration:, deactivate:|
      integration.update!(
        webhook_listening_enabled: false,
        webhook_url: nil,
        subscribed_at: nil,
        unsubscribed_at: Time.current
      )
    end

    patch admin_external_lead_integration_path, params: {
      external_lead_integration: {
        enabled: "1",
        webhook_listening_enabled: "0"
      }
    }

    expect(response).to redirect_to(admin_external_lead_integration_path)
    expect(integration.reload).to be_connected
    expect(integration.webhook_listening_enabled?).to be(false)
    expect(integration.subscribed_at).to be_nil
    expect(ExternalLeadMigration::WebhookSubscriptionService).to have_received(:unsubscribe!).with(integration:, deactivate: false)
  end
end
