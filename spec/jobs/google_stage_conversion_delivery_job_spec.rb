require "rails_helper"

RSpec.describe GoogleStageConversionDeliveryJob do
  include ActiveSupport::Testing::TimeHelpers
  around do |example|
    previous = Current.tenant
    Current.tenant = Tenant.default
    example.run
  ensure
    Current.tenant = previous
  end
  let(:setting) { WebhookSetting.create!(tenant: Current.tenant, webhook_url: "https://gtm.example.com/events", enabled: true, google_conversions_enabled: true, webhook_secret: "test-secret") }
  let(:event) do
    GoogleStageConversionEvent.create!(tenant: Current.tenant, lead: create(:lead), webhook_setting: setting,
      conversion_type: "visita", occurred_at: Time.current, destination_url: setting.google_destination_url,
      payload: JSON.generate(event_id: "stable_visita", transaction_id: "stable_visita", event_timestamp: Time.current.to_i))
  end
  before do
    allow_any_instance_of(GoogleStageConversionEvent).to receive(:enqueue_delivery)
    allow(Automation::WebhookUrlPolicy).to receive(:blocked?).and_return(false)
  end
  it "envia com segredo e diagnóstico, sem repetir depois do sucesso" do
    expect(HTTParty).to receive(:post).once.with(event.destination_url, hash_including(headers: hash_including("X-Webhook-Secret" => "test-secret"), body: include('"diagnostic":true'), follow_redirects: false)).and_return(double(code: 204))
    2.times { described_class.perform_now(event.tenant_id, event.id) }
    expect(event.reload).to have_attributes(status: "delivered", attempt_count: 1)
  end
  it "preserva o payload e limita falhas a quatro tentativas com os intervalos previstos" do
    original = event.payload
    expect(HTTParty).to receive(:post).exactly(4).times.and_return(double(code: 503))
    described_class::RETRY_DELAYS.each_with_index do |delay, index|
      described_class.perform_now(event.tenant_id, event.id)
      expect(event.reload.attempt_count).to eq(index + 1)
      expect(event.next_attempt_at).to be_within(2.seconds).of(Time.current + delay)
      travel_to event.next_attempt_at + 1.second
    end
    described_class.perform_now(event.tenant_id, event.id)
    described_class.perform_now(event.tenant_id, event.id)
    expect(event.reload).to have_attributes(status: "failed", attempt_count: 4, payload: original)
    expect(event.attempt_log.size).to eq(4)
  end
  it "não consulta nem envia evento por outra conta" do
    expect(HTTParty).not_to receive(:post)
    described_class.perform_now(event.tenant_id + 10000, event.id)
    expect(event.reload.attempt_count).to eq(0)
  end
  it "interrompe quando o destino foi alterado ou é privado" do
    event
    allow(Automation::WebhookUrlPolicy).to receive(:blocked?).and_return(true)
    expect(HTTParty).not_to receive(:post)
    described_class.perform_now(event.tenant_id, event.id)
    expect(event.reload.skip_reason).to eq("destination_blocked")
  end
end
