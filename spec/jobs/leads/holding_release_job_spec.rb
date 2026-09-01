require "rails_helper"

RSpec.describe Leads::HoldingReleaseJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  let(:agent) { create(:admin_user, :field_agent) }
  let(:schedule) do
    DistributionRule::DAYS.index_with { { "active" => "true", "start" => "08:00", "end" => "23:59" } }
  end
  let(:rule) { create(:distribution_rule, represamento_active: true, represamento_schedule: schedule) }

  before do
    Lead.skip_callback(:commit, :after, :route_lead)
    create(:distribution_rule_agent, distribution_rule: rule, admin_user: agent, position: 1)
    allow(Leads::NotificationDispatcher).to receive(:deliver)
  end

  after do
    Lead.set_callback(:commit, :after, :route_lead)
  end

  it "distribui lead represado por horario quando o expediente comeca" do
    lead = create(:lead, status: :represado, admin_user: nil, distribution_rule: rule)
    lead.activities.create!(kind: "dammed", metadata: { rule_id: rule.id, rule_name: rule.name })

    travel_to Time.zone.local(2026, 9, 1, 8, 0, 0) do
      described_class.perform_now
    end

    expect(lead.reload.admin_user_id).to eq(agent.id)
    expect(lead.status).to eq(Lead.status_value(:waiting_acceptance))
    expect(lead.activities.where(kind: "distributed")).to exist
  end

  it "mantem lead represado enquanto ainda esta fora do horario" do
    lead = create(:lead, status: :represado, admin_user: nil, distribution_rule: rule)
    lead.activities.create!(kind: "dammed", metadata: { rule_id: rule.id, rule_name: rule.name })

    travel_to Time.zone.local(2026, 9, 1, 7, 59, 0) do
      described_class.perform_now
    end

    expect(lead.reload.admin_user_id).to be_nil
    expect(lead.status).to eq(Lead.status_value(:represado))
    expect(lead.activities.where(kind: "distributed")).to be_empty
  end

  it "nao libera represado por falta de check-in elegivel" do
    lead = create(:lead, status: :represado, admin_user: nil, distribution_rule: rule)
    lead.activities.create!(
      kind: "dammed",
      metadata: { rule_id: rule.id, rule_name: rule.name, reason: "no_eligible_agent_with_checkin" }
    )

    travel_to Time.zone.local(2026, 9, 1, 8, 0, 0) do
      described_class.perform_now
    end

    expect(lead.reload.admin_user_id).to be_nil
    expect(lead.status).to eq(Lead.status_value(:represado))
    expect(lead.activities.where(kind: "distributed")).to be_empty
  end
end
