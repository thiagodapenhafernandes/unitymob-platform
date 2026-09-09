require "rails_helper"
require "timeout"

RSpec.describe "Envios concorrentes de lembrete" do
  self.use_transactional_tests = false

  it "envia uma só vez quando duas conexões disputam a mesma atividade" do
    tenant = Tenant.create!(name: "Concorrência", slug: "reminder-lock-#{SecureRandom.hex(5)}")
    owner = create(:admin_user, tenant: tenant)
    setting = LeadSetting.instance(tenant: tenant)
    task = create(:task, tenant: tenant, admin_user: owner, lead: nil, due_at: 5.minutes.ago)
    entered = Queue.new
    release = Queue.new
    second_ready = Queue.new
    sent = Queue.new
    workers = []
    Timeout.timeout(15) do
      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Activities::ReminderDelivery.new(Task.find(task.id), setting: setting, now: Time.current).call do
            entered << true
            release.pop
            sent << true
            1
          end
        end
      end
      entered.pop
      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          stale_task = Task.find(task.id)
          second_ready << true
          Activities::ReminderDelivery.new(stale_task, setting: setting, now: Time.current).call { sent << true; 1 }
        end
      end
      second_ready.pop
      release << true
      workers.each(&:value)
    end
    expect(sent.size).to eq(1)
    expect(task.reload.reminder_state.fetch("sent")).to have_key("due")
  ensure
    release << true if release
    workers&.each { |worker| worker.kill if worker.alive?; worker.join }
    if tenant
      tenant.tasks.destroy_all
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
