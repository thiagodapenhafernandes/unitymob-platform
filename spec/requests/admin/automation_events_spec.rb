require "rails_helper"

RSpec.describe "Admin::AutomationEvents", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "automation-events-#{SecureRandom.hex(6)}@salute.test") }

  before do
    host! "localhost"
    sign_in admin
  end

  describe "GET index" do
    it "lista eventos recentes da automação com lead e status" do
      lead = create(:lead, name: "Maria Evento", phone: "47999990000")
      AutomationEvent.delete_all
      event = AutomationEvent.create!(
        lead: lead,
        name: "proposal_viewed",
        source: "proposal",
        status: "processed",
        idempotency_key: "proposal_viewed:123",
        payload: { proposal_id: 123 },
        occurred_at: Time.current,
        processed_at: Time.current
      )
      run = AutomationRule.create!(name: "Follow-up proposta", trigger_event: "proposal_viewed")
      event.automation_runs.create!(automation_rule: run, lead: lead, status: "executed", executed_at: Time.current)

      get admin_automation_events_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Eventos da Automação")
      expect(response.body).to include("Proposta visualizada")
      expect(response.body).to include("Maria Evento")
      expect(response.body).to include("Processado")
      expect(response.body).to include("proposal_viewed:123")
      expect(response.body).to include("1 regra")
    end

    it "filtra por status e busca pelo lead" do
      kept_lead = create(:lead, name: "Lead Com Falha")
      other_lead = create(:lead, name: "Lead Processado")
      AutomationEvent.delete_all
      AutomationEvent.create!(lead: kept_lead, name: "lead_idle", source: "automation_tick", status: "failed", occurred_at: 1.minute.ago, error_message: "erro controlado")
      AutomationEvent.create!(lead: other_lead, name: "lead_created", source: "lead", status: "processed", occurred_at: 2.minutes.ago)

      get admin_automation_events_path, params: { status: "failed", q: "Falha" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Lead Com Falha")
      expect(response.body).to include("erro controlado")
      expect(response.body).not_to include("Lead Processado")
    end

    it "não lista eventos de outro Tenant" do
      other_tenant = Tenant.create!(name: "Outro auto #{SecureRandom.hex(3)}", slug: "outro-auto-#{SecureRandom.hex(3)}")
      other_lead = create(:lead, tenant: other_tenant, name: "Lead Outro Tenant")
      current_lead = create(:lead, tenant: admin.tenant, name: "Lead Tenant Atual")
      AutomationEvent.delete_all
      AutomationEvent.create!(tenant: admin.tenant, lead: current_lead, name: "lead_created", source: "lead", status: "processed", occurred_at: Time.current)
      AutomationEvent.create!(tenant: other_tenant, lead: other_lead, name: "lead_created", source: "lead", status: "processed", occurred_at: Time.current)

      get admin_automation_events_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Lead Tenant Atual")
      expect(response.body).not_to include("Lead Outro Tenant")
    end
  end

  describe "POST reprocess" do
    include ActiveJob::TestHelper

    it "reenfileira evento com erro" do
      lead = create(:lead)
      event = AutomationEvent.create!(lead: lead, name: "lead_created", source: "lead", status: "failed", occurred_at: Time.current, error_message: "erro")

      expect {
        post reprocess_admin_automation_event_path(event)
      }.to have_enqueued_job(Automation::ProcessEventJob)

      expect(response).to redirect_to(admin_automation_events_path)
      expect(event.reload.status).to eq("pending")
      expect(event.error_message).to be_nil
    end
  end

  describe "PATCH ignore" do
    it "marca evento como ignorado com motivo" do
      lead = create(:lead)
      event = AutomationEvent.create!(lead: lead, name: "lead_created", source: "lead", status: "failed", occurred_at: Time.current, error_message: "erro")

      patch ignore_admin_automation_event_path(event), params: { reason: "duplicado" }

      expect(response).to redirect_to(admin_automation_events_path)
      expect(event.reload.status).to eq("ignored")
      expect(event.payload_hash[:ignored_reason]).to eq("duplicado")
    end
  end
end
