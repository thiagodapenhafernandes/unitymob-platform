require "rails_helper"

RSpec.describe Ga4::ReportSnapshot do
  include ActiveSupport::Testing::TimeHelpers
  let(:config) { Ga4ConversionConfig.create!(tenant: Tenant.default) }
  let(:dates) { { start_date: Date.current - 7, end_date: Date.current } }
  let(:store) { ActiveSupport::Cache::MemoryStore.new }
  before do
    allow(Rails).to receive(:cache).and_return(store)
    allow(config).to receive(:reporting_configured?).and_return(true)
  end

  it "usa cache e preserva a última leitura em falha, sem apresentá-la como atual" do
    good = { status: :ok, queried_at: Time.current, counts: { "qualify_lead" => 3 } }
    allow(Ga4::ReportingClient).to receive(:call).and_return(good)
    expect(described_class.call(config: config, **dates)).to eq(good)
    described_class.call(config: config, **dates)
    expect(Ga4::ReportingClient).to have_received(:call).once
    travel 16.minutes do
      allow(Ga4::ReportingClient).to receive(:call).and_raise(IOError)
      expect(described_class.call(config: config, **dates)).to include(status: :stale, counts: good[:counts], queried_at: good[:queried_at])
    end
  end

  it "não inventa zeros quando a consulta falha ou não está configurada" do
    allow(Ga4::ReportingClient).to receive(:call).and_raise(IOError)
    expect(described_class.call(config: config, **dates)).to eq(status: :unavailable)
    allow(config).to receive(:reporting_configured?).and_return(false)
    expect(described_class.call(config: config, **dates)).to eq(status: :not_configured)
  end

  it "separa cache por conta, credencial e período" do
    allow(Ga4::ReportingClient).to receive(:call).and_return(status: :ok, counts: {})
    described_class.call(config: config, **dates)
    described_class.call(config: config, **dates.merge(start_date: Date.current - 30))
    config.update!(updated_at: 1.minute.from_now)
    described_class.call(config: config, **dates)
    expect(Ga4::ReportingClient).to have_received(:call).exactly(3).times
  end
end
