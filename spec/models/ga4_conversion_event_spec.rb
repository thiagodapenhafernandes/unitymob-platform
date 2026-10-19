require "rails_helper"

RSpec.describe Ga4ConversionEvent do
  let(:lead) { create(:lead, skip_automatic_routing: true) }
  let(:event) do
    described_class.new(tenant: lead.tenant, lead: lead, event_name: "qualify_lead",
      deduplication_key: "lead:#{lead.id}:qualified", event_id: SecureRandom.uuid,
      measurement_id: "G-TEST123", client_id: "123.456", occurred_at: Time.current)
  end

  it "rejeita parâmetros fora da lista fechada" do
    event.parameters = { "email" => "private@example.test" }
    expect(event).not_to be_valid
    expect(event.errors[:parameters]).to be_present
  end

  it "rejeita lead de outra conta mesmo com Current diferente" do
    event
    other = Tenant.create!(name: "Outra", slug: "ga4-other-#{SecureRandom.hex(4)}")
    Current.tenant = other
    event.tenant = other
    expect(event).not_to be_valid
    expect(event.errors[:lead]).to be_present
  end

  it "mantém configuração nova desativada, sem chave nem envio" do
    config = Ga4ConversionConfig.create!(tenant: lead.tenant)
    expect(config.enabled?).to be(false)
    expect(config.active?).to be(false)
    expect(config.update(enabled: true)).to be(false)
  end

  it "preserva exclusão em cascata do registro dependente" do
    key = described_class.connection.foreign_keys(:ga4_conversion_events).find { |fk| fk.to_table == "leads" }
    expect(key.on_delete).to eq(:cascade)
  end
end
