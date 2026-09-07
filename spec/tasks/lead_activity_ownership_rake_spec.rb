require "rails_helper"
require "rake"
require "tmpdir"

RSpec.describe "lead_activities:reconcile_owners" do
  before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?("lead_activities:reconcile_owners") }

  around do |example|
    saved = ENV.to_h.slice("TENANT_ID", "EXECUTE", "BACKUP_PATH")
    %w[TENANT_ID EXECUTE BACKUP_PATH].each { |key| ENV.delete(key) }
    example.run
  ensure
    %w[TENANT_ID EXECUTE BACKUP_PATH].each { |key| saved.key?(key) ? ENV[key] = saved[key] : ENV.delete(key) }
    Rake::Task["lead_activities:reconcile_owners"].reenable
  end

  it "simula sem alterar e executa com backup, auditoria e idempotência" do
    tenant = Tenant.default
    Current.tenant = tenant
    owner = create(:admin_user, tenant: tenant)
    previous = create(:admin_user, tenant: tenant)
    lead = create(:lead, tenant: tenant, admin_user: owner, skip_automatic_routing: true)
    activity = create(:task, tenant: tenant, lead: lead, admin_user: owner)
    activity.update_columns(admin_user_id: previous.id)
    ENV["TENANT_ID"] = tenant.id.to_s
    task = Rake::Task["lead_activities:reconcile_owners"]
    expect { task.invoke }.to output(/"tasks":1/).to_stdout
    expect(activity.reload.admin_user_id).to eq(previous.id)
    Dir.mktmpdir do |dir|
      ENV["EXECUTE"] = "1"
      ENV["BACKUP_PATH"] = File.join(dir, "before.jsonl")
      task.reenable
      expect { task.invoke }.to output(/"tasks":1/).to_stdout
      expect(activity.reload.admin_user_id).to eq(owner.id)
      backup = JSON.parse(File.read(ENV["BACKUP_PATH"]))
      expect(backup.dig("before", "tasks").first.take(2)).to eq([activity.id, previous.id])
      expect(lead.activities.where(kind: "activity_ownership_transferred").count).to eq(1)
      ENV["BACKUP_PATH"] = File.join(dir, "second.jsonl")
      task.reenable
      expect { task.invoke }.to output(/"tasks":0/).to_stdout
      expect(lead.activities.where(kind: "activity_ownership_transferred").count).to eq(1)
    end
  end
end
