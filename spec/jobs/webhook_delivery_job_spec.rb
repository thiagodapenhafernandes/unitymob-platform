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
end
