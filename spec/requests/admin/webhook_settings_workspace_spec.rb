require "rails_helper"

RSpec.describe "Admin::WebhookSettings workspace", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

  before do
    host! "localhost"
    sign_in admin
  end

  it "salva eventos e exibe o payload completo para cada tipo" do
    webhook = admin.tenant.webhook_settings.create!(enabled: true, webhook_url: "https://example.test/hook")
    patch admin_webhook_setting_path(webhook), params: { webhook_setting: { subscribed_events: ["qualified_lead", "lead_stage_changed"] } }
    expect(response).to redirect_to(admin_webhook_settings_path)
    expect(webhook.reload.subscribed_events).to eq(%w[qualified_lead lead_stage_changed])
    get edit_admin_webhook_setting_path(webhook)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Payload completo enviado", "broker_qualification_status", "event_timestamp", "X-Unitymob-Signature")
    expect(response.body).not_to include("c2s_export_external_id", "c2s_exported_at")
    expect(Nokogiri::HTML(response.body).css(".ax-collapse-card").size).to eq(WebhookSetting::EVENTS.size)
    patch admin_webhook_setting_path(webhook), params: { webhook_setting: { subscribed_events: [""] } }
    expect(webhook.reload.subscribed_events).to eq(%w[qualified_lead lead_stage_changed])
  end

  it "renderiza compartilhamento e webhooks de saida com os contratos densos" do
    WebhookSetting.create!(webhook_url: "https://example.com/outbound", description: "CRM externo", enabled: true)

    get admin_webhook_settings_path

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('name="lead_share_tracking_days"')
    expect(response.body).to include("ax-table__col--w-120", "ax-table__col--sm", "ax-table__col--md")
    expect(response.body).to include("CRM externo", "https://example.com/outbound")
    expect(response.body).not_to include('style="width:')
  end

  it "renderiza o novo webhook no mesmo shell estrutural do índice" do
    get new_admin_webhook_setting_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("webhook-settings-workspace")
    expect(response.body).to include("ax-workspace-main")
    expect(response.body).to include("ax-workspace-aside")
    expect(response.body).to include("webhook-settings-middle-contextbar")
    expect(response.body).to include("Identificação e envio")
    expect(response.body).to include("Referência do webhook")
    expect(response.body).not_to include("container-fluid")
  end

  it "mantém a edição no workspace e isola a exclusão no aside" do
    webhook = WebhookSetting.create!(webhook_url: "https://example.com/hook", description: "CRM externo", enabled: true)

    get edit_admin_webhook_setting_path(webhook)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("webhook-settings-workspace")
    expect(response.body).to include("ax-workspace-aside")
    expect(response.body).to include("Governança")
    expect(response.body).to include("Excluir webhook")
    expect(response.body).not_to include("container-fluid")
  end
end
