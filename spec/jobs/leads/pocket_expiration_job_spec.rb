require "rails_helper"

RSpec.describe Leads::PocketExpirationJob, type: :job do
  include ActiveJob::TestHelper

  let(:first_agent) { create(:admin_user, :field_agent, name: "Corretor Antigo") }
  let(:next_agent) { create(:admin_user, :field_agent, name: "Corretor Novo") }
  let(:rule) do
    create(
      :distribution_rule,
      pocket_active: true,
      pocket_time: 1,
      notify_push: true,
      notify_whatsapp: true,
      notify_email: true,
      notify_webhook: true
    )
  end

  before do
    Lead.skip_callback(:commit, :after, :route_lead)
    create(:distribution_rule_agent, distribution_rule: rule, admin_user: next_agent, position: 1)
    create(:distribution_rule_agent, distribution_rule: rule, admin_user: first_agent, position: 2)
    LeadSetting.instance.update!(notify_on_redistribution: true, secure_links_enabled: true, secure_link_push: true)
  end

  after do
    Lead.set_callback(:commit, :after, :route_lead)
  end

  it "redistribui lead vencido e dispara a notificacao da regra para o novo corretor" do
    lead = create(
      :lead,
      status: :waiting_acceptance,
      admin_user: first_agent,
      distribution_rule: rule,
      updated_at: 2.minutes.ago
    )
    lead.activities.create!(
      kind: "distributed",
      created_at: 2.minutes.ago,
      metadata: {
        rule_id: rule.id,
        admin_user_id: first_agent.id,
        admin_user_name: first_agent.name
      }
    )

    allow(Leads::NotificationDispatcher).to receive(:notify_lost_turn)
    allow(Leads::NotificationDispatcher).to receive(:deliver)

    described_class.perform_now(lead.id, first_agent.id)

    lead.reload
    expect(lead.admin_user_id).to eq(next_agent.id)
    expect(lead.status).to eq(Lead.status_value(:waiting_acceptance))
    expect(lead.activities.where(kind: "pocket_expired").last.meta("previous_admin_user_id")).to eq(first_agent.id)

    expect(Leads::NotificationDispatcher).to have_received(:deliver) do |notified_lead, sticky:|
      expect(notified_lead.id).to eq(lead.id)
      expect(notified_lead.admin_user_id).to eq(next_agent.id)
      expect(sticky).to eq(false)
    end
  end

  it "envia lead vencido para o Bolsao da regra quando Shark Tank pos-pocket esta ativo" do
    rule.update!(
      pocket_to_shark_tank: true,
      pool_renotify_mode: "interval",
      pool_renotify_minutes: 7
    )
    lead = create(
      :lead,
      status: :waiting_acceptance,
      admin_user: first_agent,
      distribution_rule: rule,
      updated_at: 2.minutes.ago
    )
    lead.activities.create!(
      kind: "distributed",
      created_at: 2.minutes.ago,
      metadata: {
        rule_id: rule.id,
        admin_user_id: first_agent.id,
        admin_user_name: first_agent.name
      }
    )

    allow(Leads::NotificationDispatcher).to receive(:notify_lost_turn)
    allow(Leads::NotificationDispatcher).to receive(:notify_pool)
    allow(Leads::NotificationDispatcher).to receive(:deliver)

    clear_enqueued_jobs
    described_class.perform_now(lead.id, first_agent.id)

    lead.reload
    expect(lead.admin_user_id).to be_nil
    expect(lead.status).to eq(Lead.status_value(:waiting_acceptance))
    expect(lead.activities.where(kind: "pocket_pool_ready")).to exist
    expect(Leads::NotificationDispatcher).to have_received(:notify_pool) do |notified_lead, notified_rule, candidates:, context:|
      expect(notified_lead.id).to eq(lead.id)
      expect(notified_rule.id).to eq(rule.id)
      expect(candidates.pluck(:admin_user_id)).to include(first_agent.id, next_agent.id)
      expect(context).to eq("pocket_pool")
    end
    expect(Leads::NotificationDispatcher).not_to have_received(:deliver)
    expect(enqueued_jobs.any? { |job| job[:job] == Leads::PoolRenotifyJob }).to be(true)
  ensure
    clear_enqueued_jobs
  end

  it "ignora job antigo quando o lead ja pertence a outro corretor" do
    lead = create(
      :lead,
      status: :waiting_acceptance,
      admin_user: next_agent,
      distribution_rule: rule,
      updated_at: 2.minutes.ago
    )
    lead.activities.create!(
      kind: "distributed",
      created_at: 2.minutes.ago,
      metadata: {
        rule_id: rule.id,
        admin_user_id: next_agent.id,
        admin_user_name: next_agent.name
      }
    )

    allow(Leads::NotificationDispatcher).to receive(:deliver)

    described_class.perform_now(lead.id, first_agent.id)

    expect(lead.reload.admin_user_id).to eq(next_agent.id)
    expect(lead.activities.where(kind: "pocket_expired")).to be_empty
    expect(Leads::NotificationDispatcher).not_to have_received(:deliver)
  end

  it "nao expira lead quando o tenant_id do job nao corresponde a conta do lead" do
    other_tenant = Tenant.create!(
      name: "Conta externa pocket #{SecureRandom.hex(3)}",
      slug: "conta-externa-pocket-#{SecureRandom.hex(3)}"
    )
    lead = create(
      :lead,
      status: :waiting_acceptance,
      admin_user: first_agent,
      distribution_rule: rule,
      updated_at: 2.minutes.ago
    )
    lead.activities.create!(
      kind: "distributed",
      created_at: 2.minutes.ago,
      metadata: {
        rule_id: rule.id,
        admin_user_id: first_agent.id,
        admin_user_name: first_agent.name
      }
    )

    allow(Leads::NotificationDispatcher).to receive(:notify_lost_turn)
    allow(Leads::NotificationDispatcher).to receive(:deliver)

    described_class.perform_now(lead.id, first_agent.id, tenant_id: other_tenant.id)

    expect(lead.reload.admin_user_id).to eq(first_agent.id)
    expect(lead.status).to eq(Lead.status_value(:waiting_acceptance))
    expect(lead.activities.where(kind: "pocket_expired")).to be_empty
    expect(Leads::NotificationDispatcher).not_to have_received(:notify_lost_turn)
    expect(Leads::NotificationDispatcher).not_to have_received(:deliver)
  end
end
