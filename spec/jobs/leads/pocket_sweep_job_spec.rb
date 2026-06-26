require "rails_helper"

RSpec.describe Leads::PocketSweepJob, type: :job do
  let(:first_agent) { create(:admin_user, :field_agent) }
  let(:next_agent) { create(:admin_user, :field_agent) }
  let(:rule) { create(:distribution_rule, pocket_active: true, pocket_time: 1, notify_push: true) }

  before do
    Lead.skip_callback(:commit, :after, :route_lead)
    LeadSetting.instance.update!(secure_links_enabled: true, secure_link_push: true)
    create(:distribution_rule_agent, distribution_rule: rule, admin_user: next_agent, position: 1)
    create(:distribution_rule_agent, distribution_rule: rule, admin_user: first_agent, position: 2)
  end

  after do
    Lead.set_callback(:commit, :after, :route_lead)
  end

  it "recupera leads aguardando aceite que ja venceram mesmo sem job agendado" do
    expired = create(
      :lead,
      status: :waiting_acceptance,
      admin_user: first_agent,
      distribution_rule: rule,
      updated_at: 3.minutes.ago
    )
    expired.activities.create!(
      kind: "distributed",
      created_at: 3.minutes.ago,
      metadata: { admin_user_id: first_agent.id, rule_id: rule.id }
    )

    fresh = create(
      :lead,
      status: :waiting_acceptance,
      admin_user: first_agent,
      distribution_rule: rule,
      updated_at: Time.current
    )
    fresh.activities.create!(
      kind: "distributed",
      created_at: Time.current,
      metadata: { admin_user_id: first_agent.id, rule_id: rule.id }
    )

    allow(Leads::NotificationDispatcher).to receive(:notify_lost_turn)
    allow(Leads::NotificationDispatcher).to receive(:deliver)

    described_class.perform_now

    expect(expired.reload.admin_user_id).to eq(next_agent.id)
    expect(expired.activities.where(kind: "pocket_expired")).to exist
    expect(fresh.reload.admin_user_id).to eq(first_agent.id)
    expect(fresh.activities.where(kind: "pocket_expired")).to be_empty
  end
end
