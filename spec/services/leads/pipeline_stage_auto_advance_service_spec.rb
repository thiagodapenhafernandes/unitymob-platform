require "rails_helper"

RSpec.describe Leads::PipelineStageAutoAdvanceService do
  let(:tenant) { Tenant.default }
  let(:pipeline) { create(:lead_pipeline, tenant: tenant) }
  let(:source_stage) do
    create(:lead_pipeline_stage, tenant: tenant, lead_pipeline: pipeline, name: "Sem retorno")
  end
  let(:destination_stage) { create(:lead_pipeline_stage, tenant: tenant, lead_pipeline: pipeline, name: "Nutrição") }

  it "move leads vencidos que continuam na etapa configurada" do
    automation = create(:lead_pipeline_stage_automation, lead_pipeline_stage: source_stage, tenant: tenant, auto_advance_to_stage: destination_stage)
    lead = create(:lead, tenant: tenant, lead_pipeline: pipeline, lead_pipeline_stage: source_stage, status: source_stage.name)
    create(
      :lead_audit_log,
      lead: lead,
      tenant: tenant,
      action: "status_changed",
      source: "admin",
      changeset: { status: { before: "Novo", after: source_stage.name } },
      created_at: 3.days.ago
    )

    expect {
      described_class.call
    }.to change { lead.reload.lead_pipeline_stage_id }.from(source_stage.id).to(destination_stage.id)

    expect(lead.status).to eq(destination_stage.name)
    metadata = lead.activities.where(kind: "status_change").last.metadata
    expect(metadata["by"]).to eq("Automação da etapa")
    expect(metadata["stage_automation_id"]).to eq(automation.id)
  end

  it "permite mover para etapa de outro funil do mesmo tenant" do
    other_pipeline = create(:lead_pipeline, tenant: tenant, name: "Pós-venda")
    destination = create(:lead_pipeline_stage, tenant: tenant, lead_pipeline: other_pipeline, name: "Reativar")
    create(:lead_pipeline_stage_automation, lead_pipeline_stage: source_stage, tenant: tenant, auto_advance_to_stage: destination)
    lead = create(:lead, tenant: tenant, lead_pipeline: pipeline, lead_pipeline_stage: source_stage, status: source_stage.name)
    create(
      :lead_audit_log,
      lead: lead,
      tenant: tenant,
      action: "status_changed",
      source: "admin",
      changeset: { status: { before: "Novo", after: source_stage.name } },
      created_at: 3.days.ago
    )

    expect {
      described_class.call
    }.to change { lead.reload.lead_pipeline_id }.from(pipeline.id).to(other_pipeline.id)

    expect(lead.lead_pipeline_stage_id).to eq(destination.id)
  end

  it "mantem o lead na etapa quando houve interacao do cliente dentro do prazo" do
    create(
      :lead_pipeline_stage_automation,
      lead_pipeline_stage: source_stage,
      tenant: tenant,
      auto_advance_to_stage: destination_stage,
      trigger: "customer_inactivity"
    )
    lead = create(:lead, tenant: tenant, lead_pipeline: pipeline, lead_pipeline_stage: source_stage, status: source_stage.name)
    create(
      :lead_audit_log,
      lead: lead,
      tenant: tenant,
      action: "status_changed",
      source: "admin",
      changeset: { status: { before: "Novo", after: source_stage.name } },
      created_at: 3.days.ago
    )
    LeadActivity.create!(tenant: tenant, lead: lead, kind: "whatsapp_in", created_at: 1.day.ago, updated_at: 1.day.ago)

    expect {
      described_class.call
    }.not_to change { lead.reload.lead_pipeline_stage_id }
  end

  it "executa a automacao quando atinge tentativas sem resposta antes do prazo" do
    automation = create(
      :lead_pipeline_stage_automation,
      lead_pipeline_stage: source_stage,
      tenant: tenant,
      auto_advance_to_stage: destination_stage,
      trigger: "customer_inactivity",
      after_amount: 7,
      after_unit: "days",
      action_config: { "unsuccessful_attempt_limit" => 3 }
    )
    lead = create(:lead, tenant: tenant, lead_pipeline: pipeline, lead_pipeline_stage: source_stage, status: source_stage.name)
    create(
      :lead_audit_log,
      lead: lead,
      tenant: tenant,
      action: "status_changed",
      source: "admin",
      changeset: { status: { before: "Novo", after: source_stage.name } },
      created_at: 1.day.ago
    )
    3.times do
      LeadActivity.create!(
        tenant: tenant,
        lead: lead,
        kind: "note",
        metadata: { contact_kind: "whatsapp", contact_result: "nao_respondeu" },
        created_at: 1.hour.ago,
        updated_at: 1.hour.ago
      )
    end

    expect {
      described_class.call
    }.to change { lead.reload.lead_pipeline_stage_id }.from(source_stage.id).to(destination_stage.id)

    expect(lead.activities.where(kind: "status_change").last.metadata["stage_automation_id"]).to eq(automation.id)
  end

  it "nao conta anotacao interna como tentativa sem resposta" do
    create(
      :lead_pipeline_stage_automation,
      lead_pipeline_stage: source_stage,
      tenant: tenant,
      auto_advance_to_stage: destination_stage,
      trigger: "customer_inactivity",
      after_amount: 7,
      after_unit: "days",
      action_config: { "unsuccessful_attempt_limit" => 2 }
    )
    lead = create(:lead, tenant: tenant, lead_pipeline: pipeline, lead_pipeline_stage: source_stage, status: source_stage.name)
    create(
      :lead_audit_log,
      lead: lead,
      tenant: tenant,
      action: "status_changed",
      source: "admin",
      changeset: { status: { before: "Novo", after: source_stage.name } },
      created_at: 1.day.ago
    )
    2.times do
      LeadActivity.create!(
        tenant: tenant,
        lead: lead,
        kind: "note",
        metadata: { contact_kind: "nota", contact_result: "nao_respondeu" },
        created_at: 1.hour.ago,
        updated_at: 1.hour.ago
      )
    end

    expect {
      described_class.call
    }.not_to change { lead.reload.lead_pipeline_stage_id }
  end

  it "ignora tentativas anteriores quando o cliente respondeu na etapa" do
    create(
      :lead_pipeline_stage_automation,
      lead_pipeline_stage: source_stage,
      tenant: tenant,
      auto_advance_to_stage: destination_stage,
      trigger: "customer_inactivity",
      after_amount: 7,
      after_unit: "days",
      action_config: { "unsuccessful_attempt_limit" => 3 }
    )
    lead = create(:lead, tenant: tenant, lead_pipeline: pipeline, lead_pipeline_stage: source_stage, status: source_stage.name)
    create(
      :lead_audit_log,
      lead: lead,
      tenant: tenant,
      action: "status_changed",
      source: "admin",
      changeset: { status: { before: "Novo", after: source_stage.name } },
      created_at: 1.day.ago
    )
    3.times do
      LeadActivity.create!(tenant: tenant, lead: lead, kind: "note", metadata: { contact_kind: "ligacao", contact_result: "nao_respondeu" }, created_at: 3.hours.ago, updated_at: 3.hours.ago)
    end
    LeadActivity.create!(tenant: tenant, lead: lead, kind: "whatsapp_in", created_at: 1.hour.ago, updated_at: 1.hour.ago)

    expect {
      described_class.call
    }.not_to change { lead.reload.lead_pipeline_stage_id }
  end

  it "arquiva o lead quando a acao final e arquivar" do
    archived_stage = create(:lead_pipeline_stage, tenant: tenant, lead_pipeline: pipeline, name: "Arquivado", stage_type: "archived")
    reason = tenant.attribute_options.create!(context: "lead", category: "archive_reason", name: "Sem potencial")
    create(:lead_pipeline_stage_policy, lead_pipeline_stage: source_stage, tenant: tenant, allowed_archive_reason_ids: [reason.id])
    automation = create(
      :lead_pipeline_stage_automation,
      lead_pipeline_stage: source_stage,
      tenant: tenant,
      auto_advance_to_stage: nil,
      action_type: "archive_lead",
      action_config: { "archive_reason_id" => reason.id.to_s, "note" => "Sem retorno" }
    )
    lead = create(:lead, tenant: tenant, lead_pipeline: pipeline, lead_pipeline_stage: source_stage, status: source_stage.name)
    create(
      :lead_audit_log,
      lead: lead,
      tenant: tenant,
      action: "status_changed",
      source: "admin",
      changeset: { status: { before: "Novo", after: source_stage.name } },
      created_at: 3.days.ago
    )

    expect {
      described_class.call
    }.to change { lead.reload.lead_pipeline_stage_id }.from(source_stage.id).to(archived_stage.id)

    expect(lead.archive_reason).to eq(reason)
    expect(lead.archive_note).to eq("Sem retorno")
    expect(lead.activities.where(kind: "archived").last.metadata["stage_automation_id"]).to eq(automation.id)
  end

  it "prioriza Cliente nao respondeu quando a automacao de arquivo nao define motivo" do
    archived_stage = create(:lead_pipeline_stage, tenant: tenant, lead_pipeline: pipeline, name: "Arquivado", stage_type: "archived")
    other_reason = tenant.attribute_options.create!(context: "lead", category: "archive_reason", name: "Sem potencial")
    preferred_reason = tenant.attribute_options.find_or_create_by!(context: "lead", category: "archive_reason", name: "Cliente não respondeu")
    create(:lead_pipeline_stage_policy, lead_pipeline_stage: source_stage, tenant: tenant, allowed_archive_reason_ids: [other_reason.id, preferred_reason.id])
    create(
      :lead_pipeline_stage_automation,
      lead_pipeline_stage: source_stage,
      tenant: tenant,
      auto_advance_to_stage: nil,
      action_type: "archive_lead",
      action_config: { "note" => "Sem retorno" }
    )
    lead = create(:lead, tenant: tenant, lead_pipeline: pipeline, lead_pipeline_stage: source_stage, status: source_stage.name)
    create(
      :lead_audit_log,
      lead: lead,
      tenant: tenant,
      action: "status_changed",
      source: "admin",
      changeset: { status: { before: "Novo", after: source_stage.name } },
      created_at: 3.days.ago
    )

    described_class.call

    expect(lead.reload.lead_pipeline_stage_id).to eq(archived_stage.id)
    expect(lead.archive_reason).to eq(preferred_reason)
  end

  it "cria tarefa quando a acao final e criar tarefa" do
    automation = create(
      :lead_pipeline_stage_automation,
      lead_pipeline_stage: source_stage,
      tenant: tenant,
      auto_advance_to_stage: nil,
      action_type: "create_task",
      action_config: { "task_title" => "Retomar contato", "due_in_days" => 2, "note" => "Lead parado" }
    )
    assignee = create(:admin_user, tenant: tenant)
    lead = create(:lead, tenant: tenant, lead_pipeline: pipeline, lead_pipeline_stage: source_stage, status: source_stage.name, admin_user: assignee)
    create(
      :lead_audit_log,
      lead: lead,
      tenant: tenant,
      action: "status_changed",
      source: "admin",
      changeset: { status: { before: "Novo", after: source_stage.name } },
      created_at: 3.days.ago
    )

    expect {
      described_class.call
    }.to change { lead.tasks.count }.by(1)

    task = lead.tasks.last
    expect(task).to have_attributes(title: "Retomar contato", admin_user_id: assignee.id, status: "pendente")
    expect(lead.activities.where(kind: "task_created")).to exist
    execution = LeadPipelineStageAutomationExecution.find_by!(lead: lead, lead_pipeline_stage_automation: automation)
    expect(execution).to have_attributes(status: "succeeded", action_type: "create_task", trigger: "stage_duration")
    expect(execution.finished_at).to be_present
  end

  it "nao duplica tarefa quando o job roda novamente para a mesma entrada de etapa" do
    create(
      :lead_pipeline_stage_automation,
      lead_pipeline_stage: source_stage,
      tenant: tenant,
      auto_advance_to_stage: nil,
      action_type: "create_task",
      action_config: { "task_title" => "Retomar contato", "due_in_days" => 2 }
    )
    assignee = create(:admin_user, tenant: tenant)
    lead = create(:lead, tenant: tenant, lead_pipeline: pipeline, lead_pipeline_stage: source_stage, status: source_stage.name, admin_user: assignee)
    create(
      :lead_audit_log,
      lead: lead,
      tenant: tenant,
      action: "status_changed",
      source: "admin",
      changeset: { status: { before: "Novo", after: source_stage.name } },
      created_at: 3.days.ago
    )

    expect {
      2.times { described_class.call }
    }.to change { lead.tasks.count }.by(1)

    expect(LeadPipelineStageAutomationExecution.where(lead: lead).count).to eq(1)
  end

  it "pula a acao quando ja existe execucao registrada para a mesma entrada de etapa" do
    automation = create(
      :lead_pipeline_stage_automation,
      lead_pipeline_stage: source_stage,
      tenant: tenant,
      auto_advance_to_stage: nil,
      action_type: "create_task",
      action_config: { "task_title" => "Retomar contato" }
    )
    assignee = create(:admin_user, tenant: tenant)
    lead = create(:lead, tenant: tenant, lead_pipeline: pipeline, lead_pipeline_stage: source_stage, status: source_stage.name, admin_user: assignee)
    entered_at = 3.days.ago.change(usec: 0)
    create(
      :lead_audit_log,
      lead: lead,
      tenant: tenant,
      action: "status_changed",
      source: "admin",
      changeset: { status: { before: "Novo", after: source_stage.name } },
      created_at: entered_at
    )
    create(
      :lead_pipeline_stage_automation_execution,
      tenant: tenant,
      lead_pipeline_stage_automation: automation,
      lead: lead,
      lead_pipeline_stage: source_stage,
      status: "succeeded",
      stage_entered_at: entered_at,
      started_at: entered_at,
      finished_at: entered_at
    )

    expect {
      described_class.call
    }.not_to change { lead.tasks.count }
  end

  it "registra falha da execucao sem interromper o processamento" do
    automation = create(
      :lead_pipeline_stage_automation,
      lead_pipeline_stage: source_stage,
      tenant: tenant,
      auto_advance_to_stage: nil,
      action_type: "redistribute_lead",
      action_config: { "distribution_rule_id" => "999999" }
    )
    lead = create(:lead, tenant: tenant, lead_pipeline: pipeline, lead_pipeline_stage: source_stage, status: source_stage.name)
    create(
      :lead_audit_log,
      lead: lead,
      tenant: tenant,
      action: "status_changed",
      source: "admin",
      changeset: { status: { before: "Novo", after: source_stage.name } },
      created_at: 3.days.ago
    )
    allow_any_instance_of(described_class).to receive(:redistribute_lead!).and_raise(StandardError, "fila indisponível")

    expect {
      described_class.call
    }.not_to raise_error

    execution = LeadPipelineStageAutomationExecution.find_by!(lead: lead, lead_pipeline_stage_automation: automation)
    expect(execution).to have_attributes(
      status: "failed",
      error_class: "StandardError",
      error_message: "fila indisponível"
    )
  end
end
