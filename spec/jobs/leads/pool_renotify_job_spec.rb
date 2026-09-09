require "rails_helper"

RSpec.describe Leads::PoolRenotifyJob, type: :job do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:rule) { create(:distribution_rule, distribution_mode: :shark_tank, pool_renotify_mode: "interval", pool_renotify_minutes: 5) }
  let(:broker) { create(:admin_user, :field_agent) }
  let(:lead) { create(:lead, status: :waiting_acceptance, admin_user: nil, distribution_rule: rule, created_at: 10.minutes.ago) }

  before do
    allow_any_instance_of(Lead).to receive(:route_lead)
    create(:distribution_rule_agent, distribution_rule: rule, admin_user: broker)
    LeadSetting.instance(tenant: rule.tenant).update!(notify_on_shark_tank: true)
    allow(Leads::NotificationDispatcher).to receive(:notify_pool)
    clear_enqueued_jobs
  end

  after { clear_enqueued_jobs }

  def run_job
    described_class.perform_now(lead.id, tenant_id: rule.tenant_id)
  end

  it "renotifica uma vez e não inicia outra cadeia de jobs" do
    run_job
    run_job
    expect(Leads::NotificationDispatcher).to have_received(:notify_pool).once.with(
      lead, rule, candidates: kind_of(ActiveRecord::Relation), context: "pool_renotify"
    )
    expect(lead.activities.where(kind: "pool_renotified").count).to eq(1)
    expect(enqueued_jobs.none? { |job| job[:job] == described_class }).to be(true)
  end

  it "volta a notificar somente depois do intervalo atual" do
    freeze_time do
      run_job
      travel 4.minutes
      run_job
      expect(Leads::NotificationDispatcher).to have_received(:notify_pool).once
      travel 1.minute
      run_job
      expect(Leads::NotificationDispatcher).to have_received(:notify_pool).twice
    end
  end

  it "não repete o aviso inicial antes de completar o intervalo de entrada" do
    lead.activities.create!(kind: "shark_tank_ready")
    run_job
    expect(Leads::NotificationDispatcher).not_to have_received(:notify_pool)
  end

  it "respeita a nova entrada no Bolsão após expirar um atendimento" do
    lead.activities.create!(kind: "pool_renotified", created_at: 20.minutes.ago)
    lead.activities.create!(kind: "pocket_pool_ready")
    run_job
    expect(Leads::NotificationDispatcher).not_to have_received(:notify_pool)
  end

  [ { active: false }, { pool_renotify_mode: "never" },
    { distribution_mode: :rotary, pocket_to_shark_tank: false } ].each do |attributes|
    it "interrompe jobs antigos quando a regra muda para #{attributes}" do
      rule.update!(attributes)
      run_job
      expect(Leads::NotificationDispatcher).not_to have_received(:notify_pool)
      expect(lead.activities.where(kind: "pool_renotified")).to be_empty
    end
  end

  it "não notifica um lead já assumido" do
    lead.update!(status: :em_atendimento, admin_user: broker)
    run_job
    expect(Leads::NotificationDispatcher).not_to have_received(:notify_pool)
  end

  it "não notifica quando o aviso do Shark Tank está desligado" do
    LeadSetting.instance(tenant: rule.tenant).update!(notify_on_shark_tank: false)
    run_job
    expect(Leads::NotificationDispatcher).not_to have_received(:notify_pool)
    expect(lead.activities.where(kind: "pool_renotified")).to be_empty
  end

  it "não registra uma rodada sem corretores elegíveis" do
    broker.update!(active: false)
    run_job
    expect(Leads::NotificationDispatcher).not_to have_received(:notify_pool)
    expect(lead.activities.where(kind: "pool_renotified")).to be_empty
  end

  it "aplica a ativação de intervalo aos leads que já estavam no Bolsão" do
    rule.update!(pool_renotify_mode: "never")
    lead
    described_class.perform_now
    expect(Leads::NotificationDispatcher).not_to have_received(:notify_pool)
    rule.update!(pool_renotify_mode: "interval")
    described_class.perform_now
    expect(Leads::NotificationDispatcher).to have_received(:notify_pool).once
  end

  it "antecipa ou adia a próxima rodada com o novo intervalo da regra" do
    freeze_time do
      run_job
      rule.update!(pool_renotify_minutes: 20)
      travel 6.minutes
      described_class.perform_now
      expect(Leads::NotificationDispatcher).to have_received(:notify_pool).once
      rule.update!(pool_renotify_minutes: 3)
      described_class.perform_now
      expect(Leads::NotificationDispatcher).to have_received(:notify_pool).twice
    end
  end

  it "aceita Bolsão originado da expiração de uma regra de rodízio" do
    rule.update!(distribution_mode: :rotary, pocket_to_shark_tank: true)
    run_job
    expect(Leads::NotificationDispatcher).to have_received(:notify_pool).once
  end

  it "não usa o tenant corrente como fallback para um ID explícito inválido" do
    Current.set(tenant: rule.tenant) do
      expect { described_class.perform_now(lead.id, tenant_id: -1) }.to raise_error(ArgumentError)
    end
    expect(Leads::NotificationDispatcher).not_to have_received(:notify_pool)
  end

  it "não encontra um lead de outro tenant" do
    other = Tenant.create!(name: "Outra conta", slug: "pool-other-#{SecureRandom.hex(5)}")
    described_class.perform_now(lead.id, tenant_id: other.id)
    expect(Leads::NotificationDispatcher).not_to have_received(:notify_pool)
  end
end
