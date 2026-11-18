require "rails_helper"

RSpec.describe WebhookDeliveryJob do
  let(:url) { "https://receiver.example/private-token" }
  let(:payload) { { "event_name" => "qualified_lead", "event_id" => "event-1", "transaction_id" => "event-1", "data" => { "email" => "private@example.test" } } }

  it "correlaciona sucesso sem registrar caminho do destino ou contato" do
    allow(WebhookService).to receive(:deliver).with(url, payload).and_return(success: true, status: 200)
    allow(Rails.logger).to receive(:info)
    described_class.new.perform(url, payload)
    expect(Rails.logger).to have_received(:info) do |line|
      record = JSON.parse(line.delete_prefix("[WEBHOOK_DELIVERY] "))
      expect(record).to include("event_id" => "event-1", "transaction_id" => "event-1", "destination_host" => "receiver.example", "http_status" => 200, "status" => "delivered")
      expect(line).not_to include("private-token", "private@example.test")
    end
  end

  it "mantém falha retentável sem expor URL nem mensagem do transporte" do
    allow(WebhookService).to receive(:deliver).and_return(success: false, status: 503, error: url)
    allow(Rails.logger).to receive(:error)
    expect { described_class.new.perform(url, payload.deep_symbolize_keys) }.to raise_error(WebhookDeliveryJob::DeliveryError, /event_id=event-1/)
    expect(Rails.logger).to have_received(:error) do |line|
      expect(JSON.parse(line.delete_prefix("[WEBHOOK_DELIVERY] "))).to include("status" => "failed", "http_status" => 503)
      expect(line).not_to include("private-token", "private@example.test")
    end
  end

  it "associa tentativas ao mesmo ID sem alterar a entrega nem o payload" do
    lead = create(:lead, tenant: Tenant.default, skip_automatic_routing: true)
    link = Tracking::Correlation.record(Tracking::Correlation.lead_created(lead), transport: "webhook",
      event_id: payload["event_id"], destination: url)
    reference = { tenant_id: lead.tenant_id, id: link.id }
    allow(WebhookService).to receive(:deliver).with(url, payload)
      .and_return({ success: false, status: 503 }, { success: true, status: 200 })
    expect { described_class.new.perform(url, payload, reference) }.to raise_error(WebhookDeliveryJob::DeliveryError)
    described_class.execute(described_class.new(url, payload, reference).serialize)
    expect(link.reload.delivery_status).to eq("http_accepted")
    expect(link.delivery_attempts.map { |attempt| attempt["http_status"] }).to eq([503, 200])
    expect(link.attributes.to_json).not_to include("private-token", "private@example.test")
    expect(WebhookService).to have_received(:deliver).with(url, payload).twice
  end
end
