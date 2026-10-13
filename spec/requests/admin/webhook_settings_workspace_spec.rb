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
  it "envia os campos editados ao destino salvo e retorna o payload e HTTP" do
    webhook = admin.tenant.webhook_settings.create!(enabled: true, webhook_url: "https://example.test/hook")
    allow(WebhookService).to receive(:deliver).and_return(success: true, status: 202)
    post test_admin_webhook_setting_path(webhook), params: { webhook_test: {
      event_name: "lead_crm", event_id: "edited-event", transaction_id: "edited-transaction",
      first_name: "Pessoa", last_name: "Teste", value: "350.50", property_code: "AP42", gclid: "edited-click",
      diagnostic: false, webhook_url: "https://other.test/hook"
    } }, as: :json
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body).to include("http_status" => 202, "success" => true)
    expect(body["payload"]).to include("event_name" => "lead_crm", "event_id" => "edited-event",
      "transaction_id" => "edited-transaction", "diagnostic" => true, "value" => 350.5, "property_id" => "AP42", "gclid" => "edited-click")
    expect(body["payload"].dig("user_data", "address")).to include("first_name" => "Pessoa")
    expect(body["payload"].dig("data", "property_code")).to eq("AP42")
    expect(WebhookService).to have_received(:deliver).with("https://example.test/hook", anything)
  end

  it "recusa dados inválidos e webhook inativo sem enviar" do
    webhook = admin.tenant.webhook_settings.create!(enabled: true, webhook_url: "https://example.test/hook")
    allow(WebhookService).to receive(:deliver)
    post test_admin_webhook_setting_path(webhook), params: { webhook_test: { value: "inválido", event_name: "" } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["errors"]).to be_present
    webhook.update!(enabled: false)
    post test_admin_webhook_setting_path(webhook), params: { webhook_test: { value: 150 } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(WebhookService).not_to have_received(:deliver)
  end

  it "exibe inputs preenchidos no modal compartilhado" do
    webhook = admin.tenant.webhook_settings.create!(enabled: true, webhook_url: "https://example.test/hook")
    get admin_webhook_settings_path
    html = Nokogiri::HTML(response.body)
    modal = html.at_css("#webhookTest#{webhook.id}")
    expect(modal.at_css('input[name="webhook_test[event_name]"]')["value"]).to eq("lead_crm")
    expect(modal.at_css('select[name="webhook_test[business_type]"]')).to be_present
    expect(modal.at_css('input[name="webhook_test[transaction_id]"]')).to be_present
    expect(modal.at_css('input[name="webhook_test[diagnostic]"]')).to be_nil
    expect(html.at_css(%([data-ax-modal-open="#{modal['id']}"]))).to be_present
    form = modal.at_css('form')
    expect(form['action']).to eq(test_admin_webhook_setting_path(webhook))
    expect(form['method']).to eq('post')
  end

  it "mostra falha HTTP sem declarar entrega bem sucedida" do
    webhook = admin.tenant.webhook_settings.create!(enabled: true, webhook_url: "https://example.test/hook")
    allow(WebhookService).to receive(:deliver).and_return(success: false, status: 500)
    post test_admin_webhook_setting_path(webhook), params: { webhook_test: { value: 150 } }, as: :json
    expect(response.parsed_body).to include("success" => false, "http_status" => 500)
    expect(response.parsed_body["payload"]["diagnostic"]).to eq(true)
  end

  it "não entrega testes para uma configuração de outra conta" do
    other = Tenant.create!(name: "Outra conta", slug: "webhook-other-#{SecureRandom.hex(4)}")
    webhook = other.webhook_settings.create!(enabled: true, webhook_url: "https://example.test/other")
    allow(WebhookService).to receive(:deliver)
    post test_admin_webhook_setting_path(webhook), params: { webhook_test: { value: 150 } }, as: :json
    expect(WebhookService).not_to have_received(:deliver)
    expect(response).not_to have_http_status(:ok)
  end

end
