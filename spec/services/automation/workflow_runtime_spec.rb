require "rails_helper"

RSpec.describe "Automation workflow runtime" do
  include ActiveJob::TestHelper

  let(:admin) { create(:admin_user, :admin, email: "workflow-runtime-#{SecureRandom.hex(6)}@salute.test") }
  let!(:lead) { create(:lead, admin_user: admin, status: "Em Atendimento", origin: "Site") }

  def publish_workflow(definition)
    workflow = AutomationWorkflow.create!(name: "Fluxo runtime")
    version = workflow.draft_version!
    version.update!(definition: definition)
    workflow.publish!(version: version, admin_user: admin)
    workflow.reload
  end

  def definition_with(*nodes, edges:)
    {
      "schema_version" => 1,
      "nodes" => nodes,
      "edges" => edges,
      "viewport" => { "x" => 0, "y" => 0, "zoom" => 1 }
    }
  end

  def entry_node(trigger: "lead_created")
    {
      "id" => "entry_1",
      "type" => "entry",
      "label" => "Quando observar",
      "config" => { "trigger" => trigger, "entry_policy" => "future" }
    }
  end

  it "despacha workflow ativo para evento correspondente" do
    workflow = publish_workflow(
      definition_with(
        entry_node,
        {
          "id" => "action_1",
          "type" => "action",
          "label" => "Registrar nota",
          "config" => { "action_type" => "add_note", "body" => "via workflow" }
        },
        edges: [{ "from" => "entry_1", "to" => "action_1" }]
      )
    )
    clear_enqueued_jobs

    expect {
      Automation::Dispatcher.dispatch(:lead_created, lead)
    }.to change(AutomationEvent, :count).by(1)
      .and have_enqueued_job(Automation::ProcessEventJob)

    event = AutomationEvent.last

    expect {
      Automation::ProcessEventJob.perform_now(event.id)
    }.to change(AutomationExecution, :count).by(1)

    execution = AutomationExecution.last
    expect(execution.automation_workflow).to eq(workflow)
    expect(execution.automation_workflow_version).to eq(workflow.active_version)
    expect(execution.automation_event).to eq(event)
  end

  it "respeita criterios do evento de mudanca de etapa antes de iniciar workflow" do
    workflow = publish_workflow(
      definition_with(
        {
          "id" => "entry_1",
          "type" => "entry",
          "label" => "Quando observar",
          "config" => {
            "trigger" => "lead_stage_changed",
            "entry_policy" => "future",
            "to_stage" => "Concluido"
          }
        },
        {
          "id" => "action_1",
          "type" => "action",
          "label" => "Registrar nota",
          "config" => { "action_type" => "add_note", "body" => "etapa final" }
        },
        edges: [{ "from" => "entry_1", "to" => "action_1" }]
      )
    )

    non_matching_event = AutomationEvent.create!(
      lead: lead,
      name: "lead_stage_changed",
      source: "lead",
      payload: { "from" => "Novo", "to" => "Em Atendimento" }
    )

    expect {
      Automation::Dispatcher.process_event(non_matching_event)
    }.not_to change(AutomationExecution, :count)

    matching_event = AutomationEvent.create!(
      lead: lead,
      name: "lead_stage_changed",
      source: "lead",
      payload: { "from" => "Em Atendimento", "to" => "Concluido" }
    )

    expect {
      Automation::Dispatcher.process_event(matching_event)
    }.to change(AutomationExecution, :count).by(1)

    expect(AutomationExecution.last.automation_workflow).to eq(workflow)
  end

  it "respeita origem e etapa inicial no evento de lead criado" do
    workflow = publish_workflow(
      definition_with(
        {
          "id" => "entry_1",
          "type" => "entry",
          "label" => "Quando observar",
          "config" => {
            "trigger" => "lead_created",
            "entry_policy" => "future",
            "source" => "Meta Ads",
            "stage" => "Novo"
          }
        },
        {
          "id" => "action_1",
          "type" => "action",
          "label" => "Registrar nota",
          "config" => { "action_type" => "add_note", "body" => "lead de campanha" }
        },
        edges: [{ "from" => "entry_1", "to" => "action_1" }]
      )
    )

    non_matching_event = AutomationEvent.create!(lead: lead, name: "lead_created", source: "lead")

    expect {
      Automation::Dispatcher.process_event(non_matching_event)
    }.not_to change(AutomationExecution, :count)

    matching_lead = create(:lead, admin_user: admin, status: "Novo", origin: "Meta Ads")
    matching_event = AutomationEvent.create!(lead: matching_lead, name: "lead_created", source: "lead")

    expect {
      Automation::Dispatcher.process_event(matching_event)
    }.to change(AutomationExecution, :count).by(1)

    expect(AutomationExecution.last.automation_workflow).to eq(workflow)
  end

  it "respeita texto recebido no WhatsApp antes de iniciar workflow" do
    workflow = publish_workflow(
      definition_with(
        {
          "id" => "entry_1",
          "type" => "entry",
          "label" => "Quando observar",
          "config" => {
            "trigger" => "whatsapp_received",
            "entry_policy" => "future",
            "stage" => "Em Atendimento",
            "message_contains" => "visita",
            "message_not_contains" => "cancelar"
          }
        },
        {
          "id" => "action_1",
          "type" => "action",
          "label" => "Registrar nota",
          "config" => { "action_type" => "add_note", "body" => "quer visita" }
        },
        edges: [{ "from" => "entry_1", "to" => "action_1" }]
      )
    )

    conversation = WhatsappConversation.create!(contact_phone: "5547999990000", lead: lead)
    non_matching_message = conversation.messages.create!(
      direction: "inbound",
      msg_type: "text",
      body: "quero cancelar",
      status: "delivered"
    )
    non_matching_event = AutomationEvent.create!(
      lead: lead,
      name: "whatsapp_received",
      source: "whatsapp",
      payload: { whatsapp_message_id: non_matching_message.id }
    )

    expect {
      Automation::Dispatcher.process_event(non_matching_event)
    }.not_to change(AutomationExecution, :count)

    matching_message = conversation.messages.create!(
      direction: "inbound",
      msg_type: "text",
      body: "quero marcar uma visita",
      status: "delivered"
    )
    matching_event = AutomationEvent.create!(
      lead: lead,
      name: "whatsapp_received",
      source: "whatsapp",
      payload: { whatsapp_message_id: matching_message.id }
    )

    expect {
      Automation::Dispatcher.process_event(matching_event)
    }.to change(AutomationExecution, :count).by(1)

    expect(AutomationExecution.last.automation_workflow).to eq(workflow)
  end

  it "respeita etapa atual do lead em eventos de proposta" do
    workflow = publish_workflow(
      definition_with(
        {
          "id" => "entry_1",
          "type" => "entry",
          "label" => "Quando observar",
          "config" => {
            "trigger" => "proposal_accepted",
            "entry_policy" => "future",
            "stage" => "Concluido"
          }
        },
        {
          "id" => "action_1",
          "type" => "action",
          "label" => "Registrar nota",
          "config" => { "action_type" => "add_note", "body" => "proposta aceita" }
        },
        edges: [{ "from" => "entry_1", "to" => "action_1" }]
      )
    )

    non_matching_event = AutomationEvent.create!(lead: lead, name: "proposal_accepted", source: "proposal")

    expect {
      Automation::Dispatcher.process_event(non_matching_event)
    }.not_to change(AutomationExecution, :count)

    lead.update!(status: "Concluido")
    matching_event = AutomationEvent.create!(lead: lead, name: "proposal_accepted", source: "proposal")

    expect {
      Automation::Dispatcher.process_event(matching_event)
    }.to change(AutomationExecution, :count).by(1)

    expect(AutomationExecution.last.automation_workflow).to eq(workflow)
  end

  it "executa no por no e registra steps" do
    workflow = publish_workflow(
      definition_with(
        entry_node,
        {
          "id" => "action_1",
          "type" => "action",
          "label" => "Registrar nota",
          "config" => { "action_type" => "add_note", "body" => "via workflow" }
        },
        edges: [{ "from" => "entry_1", "to" => "action_1" }]
      )
    )
    execution = AutomationExecution.create!(
      automation_workflow: workflow,
      automation_workflow_version: workflow.active_version,
      lead: lead,
      status: "pending",
      context: { "event" => "lead_created" }
    )

    expect {
      Automation::WorkflowRunner.run(execution)
    }.to change { lead.activities.where(kind: "note").count }.by(1)

    expect(execution.reload.status).to eq("completed")
    expect(execution.steps.order(:id).pluck(:node_id, :status)).to eq([
      ["entry_1", "completed"],
      ["action_1", "completed"]
    ])
  end

  it "executa caminhos paralelos que saem do mesmo bloco" do
    workflow = publish_workflow(
      definition_with(
        entry_node,
        {
          "id" => "action_1",
          "type" => "action",
          "label" => "Registrar primeira nota",
          "config" => { "action_type" => "add_note", "body" => "ramo um" }
        },
        {
          "id" => "action_2",
          "type" => "action",
          "label" => "Registrar segunda nota",
          "config" => { "action_type" => "add_note", "body" => "ramo dois" }
        },
        edges: [
          { "from" => "entry_1", "to" => "action_1" },
          { "from" => "entry_1", "to" => "action_2" }
        ]
      )
    )
    execution = AutomationExecution.create!(
      automation_workflow: workflow,
      automation_workflow_version: workflow.active_version,
      lead: lead,
      status: "pending",
      context: { "event" => "lead_created" }
    )

    expect {
      Automation::WorkflowRunner.run(execution)
    }.to change { lead.activities.where(kind: "note").count }.by(2)

    expect(execution.reload.status).to eq("completed")
    expect(execution.steps.order(:id).pluck(:node_id, :status)).to eq([
      ["entry_1", "completed"],
      ["action_1", "completed"],
      ["action_2", "completed"]
    ])
    expect(lead.activities.where(kind: "note").last(2).map { |activity| activity.metadata["body"] }).to contain_exactly("ramo um", "ramo dois")
  end

  it "encerra o fluxo em acao marcada como final" do
    workflow = publish_workflow(
      definition_with(
        entry_node,
        {
          "id" => "action_1",
          "type" => "action",
          "label" => "Registrar nota final",
          "config" => { "action_type" => "add_note", "body" => "acao final", "stop_flow" => true }
        },
        {
          "id" => "action_2",
          "type" => "action",
          "label" => "Nao deve executar",
          "config" => { "action_type" => "add_note", "body" => "nao deve rodar" }
        },
        edges: [
          { "from" => "entry_1", "to" => "action_1" },
          { "from" => "action_1", "to" => "action_2" }
        ]
      )
    )
    execution = AutomationExecution.create!(
      automation_workflow: workflow,
      automation_workflow_version: workflow.active_version,
      lead: lead,
      status: "pending",
      context: { "event" => "lead_created" }
    )

    expect {
      Automation::WorkflowRunner.run(execution)
    }.to change { lead.activities.where(kind: "note").count }.by(1)

    expect(execution.reload.status).to eq("completed")
    expect(execution.steps.order(:id).pluck(:node_id, :status)).to eq([
      ["entry_1", "completed"],
      ["action_1", "completed"]
    ])
    expect(lead.activities.where(kind: "note").last.metadata["body"]).to eq("acao final")
  end

  it "agenda retentativa quando uma intervencao falha e retry esta ativo" do
    workflow = publish_workflow(
      definition_with(
        entry_node,
        {
          "id" => "action_1",
          "type" => "action",
          "label" => "Enviar WhatsApp",
          "config" => {
            "action_type" => "send_whatsapp",
            "message" => "teste",
            "retry_enabled" => true,
            "retry_attempts" => "2",
            "retry_delay_amount" => "10",
            "retry_delay_unit" => "minutes"
          }
        },
        edges: [{ "from" => "entry_1", "to" => "action_1" }]
      )
    )
    execution = AutomationExecution.create!(
      automation_workflow: workflow,
      automation_workflow_version: workflow.active_version,
      lead: lead,
      status: "pending"
    )
    allow_any_instance_of(Automation::ActionExecutor).to receive(:execute).and_raise(StandardError, "falha temporaria")
    allow(Automation::RunWorkflowJob).to receive(:set).and_return(Automation::RunWorkflowJob)
    allow(Automation::RunWorkflowJob).to receive(:perform_later)

    Automation::WorkflowRunner.run(execution)

    step = execution.steps.where(node_id: "action_1").last
    expect(execution.reload.status).to eq("waiting")
    expect(step.status).to eq("waiting")
    expect(step.output["retry_attempt"]).to eq(1)
    expect(execution.context["retries"]["action_1"]).to eq(1)
    expect(Automation::RunWorkflowJob).to have_received(:set).with(hash_including(:wait_until))
    expect(Automation::RunWorkflowJob).to have_received(:perform_later).with(execution.id, "action_1")
  end

  it "agenda continuacao quando encontra espera" do
    workflow = publish_workflow(
      definition_with(
        entry_node,
        {
          "id" => "wait_1",
          "type" => "wait",
          "label" => "Esperar retorno",
          "config" => { "amount" => "2", "unit" => "hours" }
        },
        {
          "id" => "action_1",
          "type" => "action",
          "label" => "Registrar nota",
          "config" => { "action_type" => "add_note", "body" => "depois da espera" }
        },
        edges: [
          { "from" => "entry_1", "to" => "wait_1" },
          { "from" => "wait_1", "to" => "action_1" }
        ]
      )
    )
    execution = AutomationExecution.create!(
      automation_workflow: workflow,
      automation_workflow_version: workflow.active_version,
      lead: lead,
      status: "pending"
    )
    allow(Automation::RunWorkflowJob).to receive(:set).and_return(Automation::RunWorkflowJob)
    allow(Automation::RunWorkflowJob).to receive(:perform_later)

    Automation::WorkflowRunner.run(execution)

    expect(execution.reload.status).to eq("waiting")
    expect(execution.steps.where(node_id: "wait_1").last.status).to eq("waiting")
    expect(Automation::RunWorkflowJob).to have_received(:set).with(hash_including(:wait_until))
    expect(Automation::RunWorkflowJob).to have_received(:perform_later).with(execution.id, "action_1")
  end

  it "agenda espera ate uma data e hora especifica" do
    run_at = 2.days.from_now.change(usec: 0)
    workflow = publish_workflow(
      definition_with(
        entry_node,
        {
          "id" => "wait_1",
          "type" => "wait",
          "label" => "Esperar data",
          "config" => { "mode" => "datetime", "run_at" => run_at.iso8601 }
        },
        {
          "id" => "action_1",
          "type" => "action",
          "label" => "Registrar nota",
          "config" => { "action_type" => "add_note", "body" => "depois da data" }
        },
        edges: [
          { "from" => "entry_1", "to" => "wait_1" },
          { "from" => "wait_1", "to" => "action_1" }
        ]
      )
    )
    execution = AutomationExecution.create!(
      automation_workflow: workflow,
      automation_workflow_version: workflow.active_version,
      lead: lead,
      status: "pending"
    )
    allow(Automation::RunWorkflowJob).to receive(:set).and_return(Automation::RunWorkflowJob)
    allow(Automation::RunWorkflowJob).to receive(:perform_later)

    Automation::WorkflowRunner.run(execution)

    step = execution.steps.where(node_id: "wait_1").last
    expect(step.status).to eq("waiting")
    expect(step.scheduled_for.to_i).to eq(run_at.to_i)
    expect(Automation::RunWorkflowJob).to have_received(:set).with(hash_including(wait_until: be_within(1.second).of(run_at)))
  end

  it "retoma acompanhamento quando evento aguardado acontece antes do timeout" do
    workflow = publish_workflow(
      definition_with(
        entry_node,
        {
          "id" => "await_1",
          "type" => "await_event",
          "label" => "Aguardar WhatsApp",
          "config" => { "trigger" => "whatsapp_received", "timeout_amount" => "1", "timeout_unit" => "days" }
        },
        {
          "id" => "action_1",
          "type" => "action",
          "label" => "Registrar nota",
          "config" => { "action_type" => "add_note", "body" => "respondeu" }
        },
        edges: [
          { "from" => "entry_1", "to" => "await_1" },
          { "from" => "await_1", "to" => "action_1" }
        ]
      )
    )
    execution = AutomationExecution.create!(
      automation_workflow: workflow,
      automation_workflow_version: workflow.active_version,
      lead: lead,
      status: "pending"
    )
    Automation::WorkflowRunner.run(execution)
    clear_enqueued_jobs

    event = AutomationEvent.create!(lead: lead, name: "whatsapp_received", source: "whatsapp")

    expect {
      Automation::Dispatcher.process_event(event)
    }.to have_enqueued_job(Automation::RunWorkflowJob).with(execution.id, "action_1")

    step = execution.steps.where(node_id: "await_1").last
    expect(step.reload.status).to eq("completed")
    expect(step.output["matched_event_id"]).to eq(event.id)
  end

  it "emite evento para rotina agendada de workflow" do
    workflow = publish_workflow(
      definition_with(
        {
          "id" => "entry_1",
          "type" => "entry",
          "label" => "Quando observar",
          "config" => {
            "trigger" => "scheduled_routine",
            "entry_policy" => "existing_and_future",
            "schedule_frequency" => "every_n_minutes",
            "interval" => "15",
            "stage" => "Em Atendimento"
          }
        },
        {
          "id" => "action_1",
          "type" => "action",
          "label" => "Registrar nota",
          "config" => { "action_type" => "add_note", "body" => "rotina" }
        },
        edges: [{ "from" => "entry_1", "to" => "action_1" }]
      )
    )
    clear_enqueued_jobs

    expect {
      Automation::WorkflowDispatcher.dispatch_scheduled_routines
    }.to change(AutomationEvent.where(name: "scheduled_routine"), :count).by(1)
      .and have_enqueued_job(Automation::ProcessEventJob)

    event = AutomationEvent.where(name: "scheduled_routine").last
    expect(event.payload_hash[:workflow_id]).to eq(workflow.id)
    expect(event.idempotency_key).to include("scheduled_routine:workflow:#{workflow.id}:lead:#{lead.id}")
  end

  it "encerra sem executar acao quando condicao nao casa" do
    workflow = publish_workflow(
      definition_with(
        entry_node,
        {
          "id" => "condition_1",
          "type" => "condition",
          "label" => "Origem paga",
          "config" => { "operator" => "and", "source" => "Google Ads" }
        },
        {
          "id" => "action_1",
          "type" => "action",
          "label" => "Registrar nota",
          "config" => { "action_type" => "add_note", "body" => "nao deve rodar" }
        },
        edges: [
          { "from" => "entry_1", "to" => "condition_1" },
          { "from" => "condition_1", "to" => "action_1" }
        ]
      )
    )
    execution = AutomationExecution.create!(
      automation_workflow: workflow,
      automation_workflow_version: workflow.active_version,
      lead: lead,
      status: "pending"
    )

    expect {
      Automation::WorkflowRunner.run(execution)
    }.not_to change { lead.activities.where(kind: "note").count }

    expect(execution.reload.status).to eq("completed")
    expect(execution.steps.order(:id).pluck(:node_id)).to eq(["entry_1", "condition_1"])
    expect(execution.steps.where(node_id: "condition_1").last.output["matched"]).to be false
  end
end
