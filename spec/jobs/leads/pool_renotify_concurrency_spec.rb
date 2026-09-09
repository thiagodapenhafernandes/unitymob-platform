require "rails_helper"
require "timeout"

RSpec.describe "Renotificações concorrentes do Bolsão" do
  self.use_transactional_tests = false

  it "envia uma rodada só quando dois workers disputam o mesmo lead" do
    tenant = Tenant.create!(name: "Concorrência Bolsão", slug: "pool-lock-#{SecureRandom.hex(5)}")
    allow_any_instance_of(Lead).to receive(:route_lead)
    allow(Leads::AuditChangeRecorder).to receive(:record_create!)
    allow(Leads::AuditChangeRecorder).to receive(:record_destroy!)
    broker = create(:admin_user, :field_agent, tenant: tenant)
    rule = create(:distribution_rule, tenant: tenant, distribution_mode: :shark_tank,
                  pool_renotify_mode: "interval", pool_renotify_minutes: 5)
    create(:distribution_rule_agent, distribution_rule: rule, admin_user: broker, tenant: tenant)
    LeadSetting.instance(tenant: tenant).update!(notify_on_shark_tank: true)
    lead = create(:lead, tenant: tenant, distribution_rule: rule, admin_user: nil,
                  status: :waiting_acceptance, created_at: 10.minutes.ago)
    entered = Queue.new
    release = Queue.new
    second_ready = Queue.new
    sent = Queue.new
    workers = []
    allow(Leads::NotificationDispatcher).to receive(:notify_pool) do
      entered << true
      release.pop
      sent << true
    end
    Timeout.timeout(15) do
      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Leads::PoolRenotifyJob.perform_now(lead.id, tenant_id: tenant.id)
        end
      end
      entered.pop
      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          second_ready << true
          Leads::PoolRenotifyJob.perform_now(lead.id, tenant_id: tenant.id)
        end
      end
      second_ready.pop
      release << true
      workers.each(&:value)
    end
    expect(sent.size).to eq(1)
    expect(lead.activities.where(kind: "pool_renotified").count).to eq(1)
  ensure
    release << true if release
    workers&.each { |worker| worker.kill if worker.alive?; worker.join }
    if tenant
      tenant.leads.destroy_all
      AutomationEvent.where(tenant_id: tenant.id).delete_all
      tenant.distribution_rules.destroy_all
      tenant.admin_users.destroy_all
      LeadPipelineStageTransition.where(tenant_id: tenant.id).delete_all
      tenant.lead_pipelines.destroy_all
      Profile.where(tenant_id: tenant.id).delete_all
      tenant.lead_setting&.destroy!
      AttributeOption.where(tenant_id: tenant.id).delete_all
      tenant.reload.destroy!
    end
  end
end
