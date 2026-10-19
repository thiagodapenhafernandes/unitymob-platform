require "rails_helper"

RSpec.describe Ga4ConversionDeliveryJob do
  let(:tenant) { Tenant.default }
  let(:lead) { create(:lead, tenant: tenant, skip_automatic_routing: true, attribution_data: { "client_id" => "123.456", "analytics_consent" => "granted" }) }
  let!(:config) { Ga4ConversionConfig.create!(tenant: tenant, enabled: true, activated_at: 1.hour.ago, measurement_id: "G-TEST123", api_secret: "test-secret") }
  let(:event) do
    Ga4ConversionEvent.create!(tenant: tenant, lead: lead, deduplication_key: "test:#{lead.id}",
      event_name: "qualify_lead", event_id: SecureRandom.uuid, measurement_id: config.measurement_id,
      client_id: "123.456", occurred_at: Time.current, parameters: { "lead_source" => "crm" })
  end

  before do
    allow(described_class).to receive(:perform_later)
    allow(Ga4::MeasurementClient).to receive(:deliver).and_return(Ga4::MeasurementClient::Result.new(outcome: "http_accepted", http_status: 204))
  end

  it "envia após commit e não duplica em execução repetida" do
    described_class.perform_now(tenant.id, event.id)
    described_class.perform_now(tenant.id, event.id)
    expect(event.reload).to have_attributes(status: "http_accepted", http_status: 204)
    expect(Ga4::MeasurementClient).to have_received(:deliver).once
  end

  it "não aceita ID de evento de outra conta" do
    described_class.perform_now(tenant.id + 1, event.id)
    expect(Ga4::MeasurementClient).not_to have_received(:deliver)
    expect(event.reload.status).to eq("pending")
  end

  it "não envia após desativação da conta" do
    event
    config.update!(enabled: false)
    described_class.perform_now(tenant.id, event.id)
    expect(event.reload.status).to eq("skipped")
    expect(event.skip_reason).to eq("config_inactive")
    expect(Ga4::MeasurementClient).not_to have_received(:deliver)
  end

  it "revalida consentimento e identidade do navegador na entrega" do
    event
    lead.update_columns(attribution_data: { "client_id" => "123.456", "analytics_consent" => "denied" })
    described_class.perform_now(tenant.id, event.id)
    expect(event.reload.status).to eq("skipped")
    expect(event.skip_reason).to eq("consent_missing")
    expect(Ga4::MeasurementClient).not_to have_received(:deliver)
  end

  it "não retrodata evento vencido nem o reatribui a outro fluxo" do
    config.update!(activated_at: 100.hours.ago)
    event.update!(occurred_at: 73.hours.ago)
    described_class.perform_now(tenant.id, event.id)
    expect(event.reload.status).to eq("skipped")
    expect(event.skip_reason).to eq("expired")
    expect(Ga4::MeasurementClient).not_to have_received(:deliver)
  end

  it "descarta evento anterior à ativação sem mudar sua data" do
    event.update!(occurred_at: 2.hours.ago)
    described_class.perform_now(tenant.id, event.id)
    expect(event.reload.skip_reason).to eq("before_activation")
    expect(Ga4::MeasurementClient).not_to have_received(:deliver)
  end

  it "não muda silenciosamente o fluxo de um evento já registrado" do
    event
    config.update!(measurement_id: "G-OTHER123")
    described_class.perform_now(tenant.id, event.id)
    expect(event.reload.skip_reason).to eq("destination_changed")
    expect(Ga4::MeasurementClient).not_to have_received(:deliver)
  end

  it "mantém resposta inconclusiva sem reenvio automático" do
    allow(Ga4::MeasurementClient).to receive(:deliver).and_return(Ga4::MeasurementClient::Result.new(outcome: "uncertain", http_status: nil))
    2.times { described_class.perform_now(tenant.id, event.id) }
    expect(event.reload.status).to eq("uncertain")
    expect(Ga4::MeasurementClient).to have_received(:deliver).once
  end

  it "não repete a rede se o processo falha ao confirmar o aceite localmente" do
    event
    allow(Ga4ConversionEvent).to receive(:find_by).with(tenant_id: tenant.id, id: event.id).and_return(event)
    allow(event).to receive(:update!).and_wrap_original do |original, attributes|
      raise ActiveRecord::StatementInvalid, "test confirmation failure" if attributes[:status] == "http_accepted"
      original.call(attributes)
    end
    expect { described_class.perform_now(tenant.id, event.id) }.to raise_error(ActiveRecord::StatementInvalid)
    expect(event.reload.status).to eq("sending")
    described_class.perform_now(tenant.id, event.id)
    expect(Ga4::MeasurementClient).to have_received(:deliver).once
  end

  it "resgata somente eventos sem tentativa e sinaliza execução interrompida" do
    event.update!(created_at: 2.minutes.ago)
    Ga4ConversionRecoveryJob.perform_now
    expect(described_class).to have_received(:perform_later).with(tenant.id, event.id).twice
    event.update!(status: "sending", attempted_at: 20.minutes.ago)
    Ga4ConversionRecoveryJob.perform_now
    expect(event.reload.status).to eq("uncertain")
    expect(described_class).to have_received(:perform_later).twice
  end
end
