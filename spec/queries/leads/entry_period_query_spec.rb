require "rails_helper"

RSpec.describe Leads::EntryPeriodQuery do
  let(:tenant) { Tenant.create!(name: "Conta teste", slug: "entry-#{SecureRandom.hex(6)}") }
  let(:old) { create(:lead, tenant: tenant, created_at: Time.zone.parse("2026-02-21"), skip_automatic_routing: true) }
  let(:window) { Time.zone.parse("2026-10-12")..Time.zone.parse("2026-10-18").end_of_day }
  let(:query) { described_class.new(scope: tenant.leads, starts_at: window.begin, ends_at: window.end) }

  def entry(lead, at)
    lead.activities.create!(kind: "inquiry_complemented", created_at: Time.zone.parse(at))
  end

  it "filtra uma reentrada sem duplicar nem sobrescrever o cadastro original" do
    entry(old, "2026-10-12 10:15")
    entry(old, "2026-10-12 10:23")
    expect(query.call.pluck(:id)).to eq([old.id])
    query.load_dates([old])
    expect(old.entry_received_at).to eq(Time.zone.parse("2026-10-12 10:23"))
    expect(old.reload.created_at).to eq(Time.zone.parse("2026-02-21"))
  end

  it "usa a entrada do período escolhido mesmo quando há outra posterior" do
    entry(old, "2026-10-12 10:15")
    entry(old, "2026-11-01")
    query.load_dates([old])
    expect(old.entry_received_at).to eq(Time.zone.parse("2026-10-12 10:15"))
    latest = described_class.new(scope: tenant.leads)
    latest.load_dates([old])
    expect(old.entry_received_at).to eq(Time.zone.parse("2026-11-01"))
    expect(tenant.leads.order(Arel.sql(query.date_sql)).pick(Arel.sql(query.date_sql))).to eq(Time.zone.parse("2026-10-12 10:15"))
  end

  it "não trata redistribuição interna ou alteração cadastral como nova consulta" do
    old.activities.create!(kind: "distributed", created_at: window.begin)
    old.touch
    expect(query.call).to be_empty
    query.load_dates([old])
    expect(old.entry_received_at).to eq(old.created_at)
  end

  it "preserva os limites de conta e responsável" do
    entry(old, "2026-10-12")
    foreign = create(:lead, tenant: Tenant.create!(name: "Conta teste", slug: "entry-#{SecureRandom.hex(6)}"), created_at: window.begin, skip_automatic_routing: true)
    expect(query.call.pluck(:id)).not_to include(foreign.id)
    restricted = described_class.new(scope: tenant.leads.where(id: -1), starts_at: window.begin, ends_at: window.end)
    expect(restricted.call).to be_empty
  end

  context "quando o C2S é a referência" do
    let!(:integration) { create(:external_lead_integration, tenant:, mirror_c2s_owners: true) }

    before do
      old.update!(external_lead_integration: integration, external_lead_id: "c2s-old",
        other_information: { "c2s_source_created_at_epoch" => Time.zone.parse("2026-02-20 10:00").to_i })
      entry(old, "2026-10-12 10:15")
    end

    it "ordena e filtra pelo recebimento da origem sem promover reentradas antigas" do
      expect(query.call).to be_empty
      latest = described_class.new(scope: tenant.leads)
      latest.load_dates([old])
      expect(old.entry_received_at).to eq(Time.zone.parse("2026-02-20 10:00"))
      expect(tenant.leads.pick(Arel.sql(latest.date_sql))).to eq(old.entry_received_at)
    end

    it "preserva reentradas locais quando o espelhamento é desligado" do
      integration.update!(mirror_c2s_owners: false)
      expect(query.call.pluck(:id)).to eq([old.id])
      query.load_dates([old])
      expect(old.entry_received_at).to eq(Time.zone.parse("2026-10-12 10:15"))
    end

    it "tolera data inválida sem falhar a listagem" do
      old.update!(other_information: { "c2s_source_created_at_epoch" => "2026-99-99" })
      latest = described_class.new(scope: tenant.leads)
      latest.load_dates([old])
      expect(old.entry_received_at).to eq(old.created_at)
    end
  end
end
