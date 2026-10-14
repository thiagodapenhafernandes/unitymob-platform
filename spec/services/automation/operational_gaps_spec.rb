require "rails_helper"

RSpec.describe "Automation operational contracts" do
  include ActiveJob::TestHelper
  let(:admin) { create(:admin_user, :admin) }
  let!(:lead) { create(:lead, admin_user: admin, status: "Em Atendimento", origin: "Site") }

  around do |example|
    previous = Current.tenant
    Current.tenant = admin.tenant
    example.run
  ensure
    Current.tenant = previous
  end

  def workflow(trigger: "lead_created", policy: "future", nodes: nil, edges: nil)
    flow = AutomationWorkflow.create!(name: "Contrato operacional")
    version = flow.draft_version!
    version.update!(definition: {
      nodes: [{ id: "entry", type: "entry", config: { trigger: trigger, entry_policy: policy, stage: "Em Atendimento", interval: 1 } }] +
        (nodes || [{ id: "note", type: "action", config: { action_type: "add_note", body: "Nota única" } }]),
      edges: edges || [{ from: "entry", to: "note" }]
    })
    flow.publish!(version: version)
    flow.reload
  end

  it "não reenfileira nem repete timeline para um evento pendente com a mesma chave" do
    clear_enqueued_jobs
    2.times { Automation::EventBus.emit("lead_created", lead: lead, idempotency_key: "same") }
    expect(enqueued_jobs.count { |job| job[:job] == Automation::ProcessEventJob }).to eq(1)
    expect(lead.activities.where(kind: "automation_event").where("metadata ->> 'automation_event_id' = ?", AutomationEvent.last.id.to_s).count).to eq(1)
  end

  it "executa uma regra somente uma vez quando o job é entregue novamente" do
    rule = AutomationRule.create!(name: "Uma nota", trigger_event: "lead_created", actions: [{ type: "add_note", body: "Uma só" }])
    event = AutomationEvent.create!(lead: lead, name: "lead_created")
    expect {
      2.times { Automation::RunActionsJob.perform_now(rule.id, lead.id, 0, event.id) }
    }.to change { lead.activities.where(kind: "note").count }.by(1)
    expect(rule.automation_runs.count).to eq(1)
  end

  it "retoma regra com erro sem repetir as ações já concluídas" do
    rule = AutomationRule.create!(name: "Parcial", trigger_event: "lead_created", actions: [
      { type: "add_note", body: "Primeira" }, { type: "add_note", body: "Segunda" }
    ])
    event = AutomationEvent.create!(lead: lead, name: "lead_created")
    failed = false
    allow_any_instance_of(Automation::ActionExecutor).to receive(:execute).and_wrap_original do |original, action|
      if action[:body] == "Segunda" && !failed
        failed = true
        raise "Falha temporária"
      end
      original.call(action)
    end
    2.times { Automation::RunActionsJob.perform_now(rule.id, lead.id, 0, event.id) }
    expect(lead.activities.where(kind: "note").count).to eq(2)
    expect(rule.automation_runs.last.status).to eq("executed")
  end

  it "avalia a base atual uma vez, respeita filtros e exclui outra conta" do
    other = create(:lead, tenant: Tenant.create!(name: "Outra", slug: "other-#{SecureRandom.hex(4)}"))
    excluded = create(:lead, admin_user: admin, status: "Proposta")
    flow = workflow(policy: "existing_and_future")
    expect {
      2.times { Automation::BackfillWorkflowJob.perform_now(flow.id, flow.active_version_id) }
    }.to change { admin.tenant.automation_events.where(source: "automation_backfill").count }.by(1)
    event = admin.tenant.automation_events.where(source: "automation_backfill").last
    expect(event.lead_id).to eq(lead.id)
    expect(event.lead_id).not_to be_in([other.id, excluded.id])
    Automation::ProcessEventJob.perform_now(event.id)
    expect(flow.executions.pluck(:lead_id)).to eq([lead.id])
  end

  it "usa eventos reais para base histórica e fixa a versão publicada" do
    flow = workflow(trigger: "whatsapp_received", policy: "existing_and_future")
    Automation::BackfillWorkflowJob.perform_now(flow.id, flow.active_version_id)
    expect(admin.tenant.automation_events.where(source: "automation_backfill")).to be_empty
    event = AutomationEvent.create!(lead: lead, name: "whatsapp_received", occurred_at: flow.active_version.published_at - 1.second, payload: { message_body: "Olá" })
    Automation::BackfillWorkflowJob.perform_now(flow.id, flow.active_version_id)
    copied = admin.tenant.automation_events.where(source: "automation_backfill").last
    expect(copied.payload_hash[:message_body]).to eq(event.payload_hash[:message_body])
    expect(copied.payload_hash[:workflow_version_id]).to eq(flow.active_version_id)
    expect { Automation::BackfillWorkflowJob.perform_now(flow.id, -1) }.not_to change(AutomationEvent, :count)
  end

  it "simula os caminhos alcançados sem misturar condições ou blocos desconectados" do
    second = create(:lead, admin_user: admin, status: "Proposta", origin: "Site")
    definition = {
      nodes: [
        { id: "entry", type: "entry", config: { trigger: "lead_created", entry_policy: "future", source: "Site" } },
        { id: "first", type: "condition", config: { stage: "Em Atendimento" } },
        { id: "second", type: "condition", config: { stage: "Proposta" } },
        { id: "note1", type: "action", config: { action_type: "add_note", body: "Atendimento" } },
        { id: "note2", type: "action", config: { action_type: "add_note", body: "Proposta" } },
        { id: "ghost", type: "action", config: { action_type: "add_note", body: "Desconectado" } }
      ],
      edges: [{ from: "entry", to: "first" }, { from: "entry", to: "second" }, { from: "first", to: "note1" }, { from: "second", to: "note2" }]
    }
    result = Automation::Simulator.workflow(definition)
    expect(result.candidate_count).to eq(2)
    expect(result.paths[lead.id][:node_ids]).to include("note1")
    expect(result.paths[lead.id][:node_ids]).not_to include("note2", "ghost")
    expect(result.paths[second.id][:node_ids]).to include("note2")
    expect(result.paths[second.id][:node_ids]).not_to include("note1", "ghost")
  end

  it "interrompe a simulação em esperas e não afirma o resultado futuro" do
    flow = workflow(nodes: [
      { id: "wait", type: "wait", config: { amount: 1, unit: "hours" } },
      { id: "note", type: "action", config: { action_type: "add_note", body: "Depois" } }
    ], edges: [{ from: "entry", to: "wait" }, { from: "wait", to: "note" }])
    result = Automation::Simulator.workflow(flow.active_version.definition_hash)
    expect(result.paths[lead.id][:uncertain]).to be true
    expect(result.paths[lead.id][:node_ids]).not_to include("note")
  end

  it "preserva espera durante a pausa e retoma sem repetir a continuação" do
    flow = workflow(nodes: [
      { id: "wait", type: "wait", config: { amount: 1, unit: "hours" } },
      { id: "note", type: "action", config: { action_type: "add_note", body: "Após espera" } }
    ], edges: [{ from: "entry", to: "wait" }, { from: "wait", to: "note" }])
    execution = Automation::WorkflowRunner.start(flow, lead, event: "lead_created")
    Automation::RunWorkflowJob.perform_now(execution.id)
    step = execution.steps.where(status: "waiting").last
    flow.pause!
    Automation::RunWorkflowJob.perform_now(execution.id, "note", step.id, "timeout")
    expect(execution.reload.status).to eq("waiting")
    expect(step.reload.output["resumed_nodes"]).to be_nil
    flow.resume!
    Automation::ResumeWorkflowJob.perform_now(flow.id)
    expect {
      2.times { Automation::RunWorkflowJob.perform_now(execution.id, "note", step.id, "timeout") }
    }.to change { lead.activities.where(kind: "note").count }.by(1)
    expect(execution.reload.status).to eq("completed")
  end

  it "ignora timeout antigo quando uma resposta já consumiu a espera" do
    flow = workflow(nodes: [
      { id: "wait", type: "await_event", config: { trigger: "proposal_viewed", timeout_amount: 1, timeout_unit: "hours" } },
      { id: "note", type: "action", config: { action_type: "add_note", body: "Resposta" } }
    ], edges: [{ from: "entry", to: "wait" }, { from: "wait", to: "note" }])
    execution = Automation::WorkflowRunner.start(flow, lead, event: "lead_created")
    Automation::RunWorkflowJob.perform_now(execution.id)
    step = execution.steps.where(status: "waiting").last
    event = AutomationEvent.create!(lead: lead, name: "proposal_viewed")
    Automation::WorkflowDispatcher.dispatch_event(event)
    expect {
      Automation::RunWorkflowJob.perform_now(execution.id, "note", step.id, "timeout")
    }.not_to change { lead.activities.where(kind: "note").count }
    Automation::RunWorkflowJob.perform_now(execution.id, "note", step.id, "event:#{event.id}")
    expect(execution.reload.status).to eq("completed")
  end

  it "executa ambos os caminhos de uma continuação paralela uma única vez" do
    flow = workflow(nodes: [
      { id: "wait", type: "wait", config: { amount: 1, unit: "hours" } },
      { id: "a", type: "action", config: { action_type: "add_note", body: "A" } },
      { id: "b", type: "action", config: { action_type: "add_note", body: "B" } }
    ], edges: [{ from: "entry", to: "wait" }, { from: "wait", to: "a" }, { from: "wait", to: "b" }])
    execution = Automation::WorkflowRunner.start(flow, lead, event: "lead_created")
    Automation::RunWorkflowJob.perform_now(execution.id)
    step = execution.steps.where(status: "waiting").last
    %w[a a b b].each { |node| Automation::RunWorkflowJob.perform_now(execution.id, node, step.id, "timeout") }
    expect(lead.activities.where(kind: "note").count).to eq(2)
    expect(execution.reload.status).to eq("completed")
  end
  it "não reinicia a entrada quando a entrega duplicada chega durante uma espera" do
    flow = workflow(nodes: [
      { id: "note", type: "action", config: { action_type: "add_note", body: "Antes" } },
      { id: "wait", type: "wait", config: { amount: 1, unit: "hours" } },
      { id: "later", type: "action", config: { action_type: "add_note", body: "Depois" } }
    ], edges: [{ from: "entry", to: "note" }, { from: "note", to: "wait" }, { from: "wait", to: "later" }])
    execution = Automation::WorkflowRunner.start(flow, lead, event: "lead_created")
    2.times { Automation::RunWorkflowJob.perform_now(execution.id) }
    expect(lead.activities.where(kind: "note").count).to eq(1)
    expect(execution.reload.status).to eq("waiting")
  end

  it "não usa eventos históricos da base atual para responder esperas de outros fluxos" do
    waiting = workflow(nodes: [
      { id: "wait", type: "await_event", config: { trigger: "whatsapp_received", timeout_amount: 1, timeout_unit: "hours" } },
      { id: "note", type: "action", config: { action_type: "add_note", body: "Futuro" } }
    ], edges: [{ from: "entry", to: "wait" }, { from: "wait", to: "note" }])
    execution = Automation::WorkflowRunner.start(waiting, lead, event: "lead_created")
    Automation::RunWorkflowJob.perform_now(execution.id)
    backfill = workflow(trigger: "whatsapp_received", policy: "existing_and_future")
    event = AutomationEvent.create!(lead: lead, name: "whatsapp_received", source: "automation_backfill",
      payload: { workflow_id: backfill.id, workflow_version_id: backfill.active_version_id })
    Automation::WorkflowDispatcher.dispatch_event(event)
    expect(execution.reload.status).to eq("waiting")
    expect(backfill.executions.count).to eq(1)
  end

  it "retoma ramos paralelos pendentes sem encerrar uma espera aberta por outro ramo" do
    flow = workflow(nodes: [
      { id: "wait", type: "wait", config: { amount: 1, unit: "hours" } },
      { id: "a", type: "wait", config: { amount: 1, unit: "hours" } },
      { id: "b", type: "action", config: { action_type: "add_note", body: "B" } },
      { id: "later", type: "action", config: { action_type: "add_note", body: "Depois de A" } }
    ], edges: [{ from: "entry", to: "wait" }, { from: "wait", to: "a" }, { from: "wait", to: "b" }, { from: "a", to: "later" }])
    execution = Automation::WorkflowRunner.start(flow, lead, event: "lead_created")
    Automation::RunWorkflowJob.perform_now(execution.id)
    original = execution.steps.where(status: "waiting").last
    Automation::RunWorkflowJob.perform_now(execution.id, "a", original.id, "timeout")
    flow.pause!
    Automation::RunWorkflowJob.perform_now(execution.id, "b", original.id, "timeout")
    flow.resume!
    Automation::ResumeWorkflowJob.perform_now(flow.id)
    Automation::RunWorkflowJob.perform_now(execution.id, "b", original.id, "timeout")
    expect(execution.reload.status).to eq("waiting")
    next_wait = execution.steps.where(status: "waiting").last
    Automation::RunWorkflowJob.perform_now(execution.id, "later", next_wait.id, "timeout")
    expect(execution.reload.status).to eq("completed")
    expect(lead.activities.where(kind: "note").count).to eq(2)
  end

end
