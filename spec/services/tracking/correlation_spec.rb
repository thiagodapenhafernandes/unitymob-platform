require "rails_helper"

RSpec.describe Tracking::Correlation do
  include ActiveSupport::Testing::TimeHelpers
  let(:tenant) { Tenant.default }
  let(:lead) { create(:lead, tenant: tenant, email: "private@example.test", skip_automatic_routing: true) }
  let(:context) { described_class.lead_created(lead) }

  it "correlaciona IDs distintos e destinos da mesma ocorrência sem guardar payload ou tokens" do
    site = described_class.record(context, transport: "site", event_id: "browser-uuid", destination: "data_layer", status: "browser_offered")
    first = described_class.record(context, transport: "webhook", event_id: "webhook-uuid", destination: "https://hooks.test/private-token?secret=abc")
    second = described_class.record(context, transport: "webhook", event_id: "webhook-uuid", destination: "https://hooks.test/other-token")

    expect([site, first, second].map(&:occurrence_key).uniq).to eq([context[:occurrence_key]])
    expect(first.destination_key).not_to eq(second.destination_key)
    expect(first.destination_label).to eq("hooks.test")
    expect(first.attributes.to_json).not_to include("private-token", "secret=abc", lead.email)
    expect(described_class.record(context, transport: "webhook", event_id: "webhook-uuid",
      destination: "https://hooks.test/private-token?secret=abc").id).to eq(first.id)
    expect(TrackingEventLink.count).to eq(3)
  end

  it "não reatribui um ID estável à ocorrência de uma edição posterior" do
    original = described_class.record(context, transport: "meta", event_id: "stable-id", destination: "123")
    lead.update!(notes: "Nova ocorrência")
    repeated = described_class.record(described_class.change(lead), transport: "meta", event_id: "stable-id", destination: "123")
    expect(repeated.id).to eq(original.id)
    expect(repeated.occurrence_key).to eq(context[:occurrence_key])
    described_class.attempt(repeated, status: "received", trace_id: "trace-123")
    described_class.attempt(repeated, status: "uncertain", error_class: "Timeout::Error")
    expect(repeated.reload.delivery_status).to eq("received")
    expect(repeated.delivery_attempts.size).to eq(2)
  end

  it "distingue alterações diferentes mesmo com o mesmo timestamp" do
    travel_to(Time.current) do
      lead.update!(notes: "Primeira alteração")
      first = described_class.change(lead)
      lead.update!(notes: "Segunda alteração")
      second = described_class.change(lead)
      expect(first[:occurred_at]).to eq(second[:occurred_at])
      expect(first[:occurrence_key]).not_to eq(second[:occurrence_key])
      expect(second[:occurrence_key]).not_to include("Segunda alteração")
    end
  end

  it "isola as contas mesmo quando o provedor e o ID externo coincidem" do
    other = Tenant.create!(name: "Outra correlação", slug: "other-correlation-#{SecureRandom.hex(3)}")
    other_lead = create(:lead, tenant: other, skip_automatic_routing: true)
    first = described_class.record(context, transport: "meta", event_id: "same", destination: "123")
    second = described_class.record(described_class.lead_created(other_lead), transport: "meta", event_id: "same", destination: "123")
    expect(first.id).not_to eq(second.id)
    expect(other_lead.tracking_event_links.pluck(:id)).to eq([second.id])
    invalid = context.merge(lead_id: other_lead.id)
    expect(described_class.record(invalid, transport: "site", event_id: "invalid", destination: "data_layer")).to be_nil
    expect(TrackingEventLink.where(external_event_id: "invalid")).not_to exist
  end

  it "não deixa falha SQL da auditoria abortar a transação comercial" do
    original = TrackingEventLink.method(:create_or_find_by!)
    allow(TrackingEventLink).to receive(:create_or_find_by!) do |**args, &block|
      ActiveRecord::Base.connection.execute("SELECT * FROM correlation_table_that_does_not_exist")
      original.call(**args, &block)
    end
    Lead.transaction do
      expect(described_class.record(context, transport: "site", event_id: "evt", destination: "data_layer")).to be_nil
      lead.update!(notes: "Fluxo principal preservado")
    end
    expect(lead.reload.notes).to eq("Fluxo principal preservado")
  end

  it "só atualiza a entrega que corresponde à conta, ao destino e ao evento do job" do
    url = "https://hooks.test/secret"
    link = described_class.record(context, transport: "webhook", event_id: "evt", destination: url)
    reference = { tenant_id: tenant.id, id: link.id }
    described_class.webhook_attempt(reference.merge(tenant_id: tenant.id + 1), url: url, event_id: "evt", status: "http_accepted")
    described_class.webhook_attempt(reference, url: "https://other.test", event_id: "evt", status: "http_accepted")
    described_class.webhook_attempt(reference, url: url, event_id: "other", status: "http_accepted")
    expect(link.reload.attempt_log).to eq([])
    described_class.webhook_attempt(reference.stringify_keys, url: url, event_id: "evt", status: "http_accepted", http_status: 200)
    expect(link.reload.delivery_status).to eq("http_accepted")
  end
end
