require "rails_helper"

RSpec.describe Leads::ContingencySweepJob do
  let(:tenant) { Tenant.create!(name: "Varredura", slug: "contingency-job-#{SecureRandom.hex(4)}") }
  around { |example| Current.set(tenant: tenant) { example.run } }
  before { allow_any_instance_of(Lead).to receive(:route_lead) }

  it "retoma pendentes no contexto da conta e preserva atendimentos em andamento" do
    target = create(:distribution_rule, tenant: tenant)
    source = create(:distribution_rule, tenant: tenant, contingency_enabled: true, contingency_rule: target, contingency_triggers: ["unavailable"])
    pending = create(:lead, tenant: tenant, distribution_rule: source, admin_user: nil)
    attended = create(:lead, tenant: tenant, distribution_rule: source, admin_user: create(:admin_user, tenant: tenant), status: "Em Atendimento")
    allow(Leads::ContingencyService).to receive(:check!) do |lead|
      expect(Current.tenant.id).to eq(lead.tenant_id)
    end
    described_class.perform_now
    expect(Leads::ContingencyService).to have_received(:check!).with(have_attributes(id: pending.id))
    expect(Leads::ContingencyService).not_to have_received(:check!).with(have_attributes(id: attended.id))
  end

  it "continua a varredura depois de um erro sem abandonar os outros leads" do
    target = create(:distribution_rule, tenant: tenant)
    source = create(:distribution_rule, tenant: tenant, contingency_enabled: true, contingency_rule: target, contingency_triggers: ["unavailable"])
    first = create(:lead, tenant: tenant, distribution_rule: source, admin_user: nil)
    second = create(:lead, tenant: tenant, distribution_rule: source, admin_user: nil)
    processed = []
    allow(Leads::ContingencyService).to receive(:check!) do |lead|
      raise "teste" if lead.id == first.id
      processed << lead.id
    end
    expect { described_class.perform_now }.not_to raise_error
    expect(processed).to include(second.id)
  end
end
