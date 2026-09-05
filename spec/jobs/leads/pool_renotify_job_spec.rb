require "rails_helper"

RSpec.describe Leads::PoolRenotifyJob, type: :job do
  include ActiveJob::TestHelper

  let(:rule) do
    create(
      :distribution_rule,
      distribution_mode: :shark_tank,
      pool_renotify_mode: "interval",
      pool_renotify_minutes: 5
    )
  end
  let(:broker) { create(:admin_user, :field_agent) }

  before do
    allow_any_instance_of(Lead).to receive(:route_lead)
    create(:distribution_rule_agent, distribution_rule: rule, admin_user: broker)
    LeadSetting.instance(tenant: rule.tenant).update!(notify_on_shark_tank: true)
  end

  after do
    clear_enqueued_jobs
  end

  it "renotifica lead ainda aberto no Bolsao e agenda a proxima rodada" do
    lead = create(:lead, status: :waiting_acceptance, admin_user: nil, distribution_rule: rule)
    allow(Leads::NotificationDispatcher).to receive(:notify_pool)

    clear_enqueued_jobs
    described_class.perform_now(lead.id, tenant_id: rule.tenant_id)

    expect(Leads::NotificationDispatcher).to have_received(:notify_pool).with(
      lead,
      rule,
      candidates: kind_of(ActiveRecord::Relation),
      context: "pool_renotify"
    )
    expect(lead.activities.where(kind: "pool_renotified")).to exist
    expect(enqueued_jobs.any? { |job| job[:job] == described_class }).to be(true)
  end

  it "nao renotifica lead que ja foi atendido" do
    lead = create(:lead, status: :em_atendimento, admin_user: broker, distribution_rule: rule)
    allow(Leads::NotificationDispatcher).to receive(:notify_pool)

    described_class.perform_now(lead.id, tenant_id: rule.tenant_id)

    expect(Leads::NotificationDispatcher).not_to have_received(:notify_pool)
    expect(lead.activities.where(kind: "pool_renotified")).to be_empty
  end
end
