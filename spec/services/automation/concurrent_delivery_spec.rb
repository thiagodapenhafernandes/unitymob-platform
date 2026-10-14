require "rails_helper"

RSpec.describe "Automation concurrent delivery", type: :model do
  self.use_transactional_tests = false

  before do
    @tenant = Tenant.create!(name: "Teste concorrência", slug: "concurrency-#{SecureRandom.hex(8)}")
    Current.tenant = @tenant
    @lead = create(:lead, tenant: @tenant)
  end

  after do
    @tenant.automation_rules.destroy_all
    @tenant.automation_executions.destroy_all
    @tenant.automation_workflows.update_all(active_version_id: nil)
    @tenant.automation_workflows.destroy_all
    @tenant.automation_events.destroy_all
    @tenant.leads.destroy_all
    @tenant.lead_pipelines.destroy_all
    LeadSetting.where(tenant_id: @tenant.id).delete_all
    AttributeOption.where(tenant_id: @tenant.id).delete_all
    # O fixture precisa ser commitado para as duas conexões enxergarem os registros.
    raise "Limpeza exclusiva do banco de testes" unless Rails.env.test?
    ActiveRecord::Base.transaction do
      connection = ActiveRecord::Base.connection
      connection.execute("ALTER TABLE lead_audit_logs DISABLE TRIGGER lead_audit_logs_no_update")
      LeadAuditLog.where(tenant_id: @tenant.id).delete_all
      connection.execute("ALTER TABLE lead_audit_logs ENABLE TRIGGER lead_audit_logs_no_update")
    end
    Profile.where(tenant_id: @tenant.id).delete_all
    @tenant.reload.destroy!
    Current.reset
  end

  def concurrently(&work)
    gate = Queue.new
    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Current.set(tenant: Tenant.find(@tenant.id)) do
            gate.pop
            work.call
          end
        end
      end
    end
    2.times { gate << true }
    threads.each(&:value)
  end

  it "cria um único evento e uma única ação em entregas simultâneas" do
    rule = @tenant.automation_rules.create!(name: "Concorrente", trigger_event: "lead_created", actions: [{ type: "add_note", body: "Única" }])
    concurrently do
      Automation::EventBus.emit("lead_created", lead: Lead.find(@lead.id), idempotency_key: "concurrent")
    end
    events = @tenant.automation_events.where(idempotency_key: "concurrent")
    expect(events.count).to eq(1)
    event = events.first
    concurrently { Automation::ProcessEventJob.perform_now(event.id) }
    expect(event.reload.status).to eq("processed")
    concurrently { Automation::RunActionsJob.perform_now(rule.id, @lead.id, 0, event.id) }
    expect(rule.automation_runs.count).to eq(1)
    expect(@lead.activities.where(kind: "note").count).to eq(1)
  end

  it "cria uma execução e uma intervenção do builder em entregas simultâneas" do
    workflow = @tenant.automation_workflows.create!(name: "Concorrência builder")
    version = workflow.draft_version!
    version.update!(definition: {
      nodes: [{ id: "entry", type: "entry", config: { trigger: "lead_created" } },
              { id: "note", type: "action", config: { action_type: "add_note", body: "Única" } }],
      edges: [{ from: "entry", to: "note" }]
    })
    workflow.publish!(version: version)
    event = @tenant.automation_events.create!(lead: @lead, name: "lead_created")
    concurrently do
      Automation::WorkflowRunner.start(AutomationWorkflow.find(workflow.id), Lead.find(@lead.id), event: "lead_created", automation_event: AutomationEvent.find(event.id))
    end
    expect(workflow.executions.count).to eq(1)
    execution = workflow.executions.first
    concurrently { Automation::RunWorkflowJob.perform_now(execution.id) }
    expect(@lead.activities.where(kind: "note").count).to eq(1)
    expect(execution.reload.status).to eq("completed")
  end
end
