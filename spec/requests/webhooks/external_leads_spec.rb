require "rails_helper"

RSpec.describe "Webhooks::ExternalLeads", type: :request do
  include ActiveJob::TestHelper

  before do
    host! "localhost"
    clear_enqueued_jobs
  end

  after { clear_enqueued_jobs }

  let(:integration) { create(:external_lead_integration, webhook_listening_enabled: true, subscribed_at: Time.current) }

  it "aceita evento externo por token da URL e enfileira processamento" do
    expect {
      post webhooks_external_lead_path(integration.webhook_token),
        params: {
          hook_action: "on_create_lead",
          data: {
            id: "lead-lead-migration-1",
            attributes: {
              customer: { name: "Lead Webhook", phone: "47999999999" },
              funnel_status: { name: "Novo" }
            }
          }
        },
        as: :json
    }.to have_enqueued_job(ExternalLeadMigration::WebhookEventJob).with(integration.id, hash_including("hook_action" => "on_create_lead"))

    expect(response).to have_http_status(:accepted)
    expect(integration.reload.last_webhook_at).to be_present
  end

  it "recusa token inválido sem enfileirar job" do
    expect {
      post webhooks_external_lead_path("invalido"), params: { id: "lead-lead-migration-1" }, as: :json
    }.not_to have_enqueued_job(ExternalLeadMigration::WebhookEventJob)

    expect(response).to have_http_status(:unauthorized)
  end

  it "recusa evento quando a escuta de novos leads está desabilitada" do
    integration.update!(webhook_listening_enabled: false)

    expect {
      post webhooks_external_lead_path(integration.webhook_token), params: { id: "lead-lead-migration-1" }, as: :json
    }.not_to have_enqueued_job(ExternalLeadMigration::WebhookEventJob)

    expect(response).to have_http_status(:unauthorized)
  end

  it "recusa evento quando a integração não está conectada" do
    integration.update!(status: "failed")

    expect {
      post webhooks_external_lead_path(integration.webhook_token), params: { id: "lead-lead-migration-1" }, as: :json
    }.not_to have_enqueued_job(ExternalLeadMigration::WebhookEventJob)

    expect(response).to have_http_status(:unauthorized)
  end
end
