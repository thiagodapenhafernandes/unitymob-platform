require "rails_helper"

RSpec.describe Leads::OutboundWebhook do
  let(:lead) { create(:lead, skip_automatic_routing: true) }

  before { allow(WebhookDeliveryJob).to receive(:perform_later) }

  it "sends only selected qualification events and uses the lead tenant instead of Current" do
    own = lead.tenant.webhook_settings.create!(enabled: true, webhook_url: "https://own.test/hook", subscribed_events: ["qualified_lead"])
    other = Tenant.create!(name: "Conta #{SecureRandom.hex(3)}", slug: "conta-#{SecureRandom.hex(3)}")
    other.webhook_settings.create!(enabled: true, webhook_url: "https://other.test/hook", subscribed_events: ["qualified_lead"])
    Current.tenant = other
    lead.skip_automatic_routing = false
    lead.update!(broker_qualification_status: "qualified")
    expect(WebhookDeliveryJob).to have_received(:perform_later).with(own.webhook_url, hash_including(
      event_name: "qualified_lead", action_source: "system_generated", lead_id: lead.id.to_s,
      data: hash_including("changes" => { "broker_qualification_status" => { from: nil, to: "qualified" } })
    )).once
  end

  it "does not emit qualification again for unrelated changes or default subscriptions" do
    lead.tenant.webhook_settings.create!(enabled: true, webhook_url: "https://own.test/hook")
    lead.skip_automatic_routing = false
    lead.update!(broker_qualification_status: "qualified")
    lead.update!(name: "Nome atualizado")
    expect(WebhookDeliveryJob).not_to have_received(:perform_later)
  end

  it "emits a stage change after saving and omits request metadata" do
    lead.tenant.webhook_settings.create!(enabled: true, webhook_url: "https://own.test/hook", subscribed_events: ["lead_stage_changed"])
    lead.skip_automatic_routing = false
    previous_status = lead.status
    lead.update!(status: "Em Atendimento", admin_user: create(:admin_user, tenant: lead.tenant))
    expect(WebhookDeliveryJob).to have_received(:perform_later) do |_, payload|
      expect(payload).to include(event_name: "lead_stage_changed", lead_id: lead.id.to_s)
      expect(payload[:data]["changes"][:status]).to include(from: previous_status, to: "Em Atendimento")
      expect(payload).not_to have_key(:client_ip_address)
    end
  end

  it "does not send changes from a rolled back transaction" do
    lead.tenant.webhook_settings.create!(enabled: true, webhook_url: "https://own.test/hook", subscribed_events: ["qualified_lead"])
    lead.skip_automatic_routing = false
    Lead.transaction do
      lead.update!(broker_qualification_status: "qualified")
      raise ActiveRecord::Rollback
    end
    expect(WebhookDeliveryJob).not_to have_received(:perform_later)
  end
end
