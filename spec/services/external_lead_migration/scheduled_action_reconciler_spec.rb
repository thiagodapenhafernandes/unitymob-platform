require "rails_helper"

RSpec.describe ExternalLeadMigration::ScheduledActionReconciler do
  let(:tenant) { Tenant.default }
  let(:broker) { create(:admin_user, tenant:, email: "broker-c2s-reconcile@example.test") }

  before { Current.tenant = tenant }

  it "faz dry-run sem alterar tarefas ou criar visitas" do
    lead = create(:lead, tenant:, admin_user: broker, status: "Em Atendimento")
    task = create(
      :task,
      tenant:,
      lead: lead,
      admin_user: broker,
      title: "Ação agendada do legado",
      due_at: Time.zone.parse("2026-08-15T13:43:30-03:00")
    )
    create_external_schedule_activity(
      lead: lead,
      task_id: task.id,
      external_key: "future-return",
      date: "2026-08-20T09:00:00.000-03:00",
      name: "Retornar para o cliente",
      alias_name: "feedback_customer"
    )

    result = described_class.call(tenant: tenant, execute: false)

    expect(result).to have_attributes(scanned: 1, tasks_updated: 1, appointments_created: 0)
    expect(task.reload).to have_attributes(
      title: "Ação agendada do legado",
      due_at: Time.zone.parse("2026-08-15T13:43:30-03:00")
    )
    expect(lead.appointments).to be_empty
  end

  it "reconcilia retornos e visitas C2S importados anteriormente" do
    return_lead = create(:lead, tenant:, admin_user: broker, status: "Em Atendimento")
    visit_lead = create(:lead, tenant:, admin_user: broker, status: "Em Atendimento")
    return_task = create(
      :task,
      tenant:,
      lead: return_lead,
      admin_user: broker,
      title: "Ação agendada do legado",
      due_at: Time.zone.parse("2026-08-15T13:43:30-03:00")
    )
    visit_task = create(
      :task,
      tenant:,
      lead: visit_lead,
      admin_user: broker,
      title: "Ação agendada do legado",
      due_at: Time.zone.parse("2026-08-15T13:44:30-03:00")
    )

    create_external_schedule_activity(
      lead: return_lead,
      task_id: return_task.id,
      external_key: "future-return",
      date: "2026-08-20T09:00:00.000-03:00",
      name: "Retornar para o cliente",
      alias_name: "feedback_customer"
    )
    create_external_schedule_activity(
      lead: visit_lead,
      task_id: visit_task.id,
      external_key: "future-visit",
      date: "2026-08-21T15:30:00.000-03:00",
      name: "Visita Agendada",
      alias_name: "scheduled_visit"
    )

    result = described_class.call(tenant: tenant, execute: true)

    expect(result).to have_attributes(scanned: 2, tasks_updated: 1, appointments_created: 1, tasks_cancelled: 1)
    expect(return_task.reload).to have_attributes(
      title: "Retornar para o cliente",
      kind: "follow_up",
      status: "pendente",
      due_at: Time.zone.parse("2026-08-20T09:00:00.000-03:00")
    )
    expect(visit_task.reload.status).to eq("cancelada")
    expect(visit_lead.appointments.first).to have_attributes(
      title: "Visita Agendada",
      kind: "visita",
      status: "agendado",
      starts_at: Time.zone.parse("2026-08-21T15:30:00.000-03:00")
    )
  end

  it "mantem o vinculo da visita convertida ao repetir o backfill e a sincronizacao" do
    integration = create(:external_lead_integration, tenant:)
    lead = create(:lead, tenant:, external_lead_integration: integration, admin_user: broker, status: "Em Atendimento")
    task = create(:task, tenant:, lead:, admin_user: broker)
    activity = create_external_schedule_activity(lead:, task_id: task.id, external_key: "visit-stable", date: "2026-09-29T09:00:00-03:00", name: "Visita", alias_name: "scheduled_visit")
    described_class.call(integration:, execute: true)
    appointment = lead.appointments.sole
    expect(activity.reload.metadata["appointment_id"]).to eq(appointment.id)
    expect(activity.kind).to eq("external_appointment")
    result = described_class.call(integration:, execute: false)
    expect(result).to have_attributes(tasks_updated: 0, appointments_updated: 0, appointments_created: 0, tasks_cancelled: 0)

    raw = activity.metadata["raw"].merge("schedulated_action_date" => "2026-09-30T09:00:00-03:00")
    mapper = ExternalLeadMigration::LeadMapper.new("id" => "lead-visit", "attributes" => { "schedulated_actions" => [raw] })
    ExternalLeadMigration::LeadEnrichment.call(lead:, integration:, mapper:, historical: false)
    expect(lead.appointments.reload.pluck(:id)).to eq([appointment.id])
    expect(appointment.reload.starts_at).to eq(Time.zone.parse("2026-09-30T09:00:00-03:00"))
    expect(task.reload.status).to eq("cancelada")
  end

  it "corrige a data sem reabrir uma tarefa concluida localmente e trata encerramento automatico" do
    lead = create(:lead, tenant:, admin_user: broker)
    completed_at = Time.zone.parse("2026-09-01T10:00:00-03:00")
    task = create(:task, tenant:, lead:, admin_user: broker, status: "concluida", completed_at:)
    create_external_schedule_activity(lead:, task_id: task.id, external_key: "completed", date: "2026-09-29T09:00:00-03:00", name: "Retornar", alias_name: "feedback_customer")
    closed_task = create(:task, tenant:, lead:, admin_user: broker, status: "pendente")
    activity = create_external_schedule_activity(lead:, task_id: closed_task.id, external_key: "closed", date: "2026-09-29T10:00:00-03:00", name: "Retornar", alias_name: "feedback_customer")
    activity.update!(metadata: activity.metadata.deep_merge("raw" => { "status" => "Fechada automaticamente pelo sistema" }))
    described_class.call(tenant:, execute: true)
    expect(task.reload).to have_attributes(status: "concluida", completed_at:, due_at: Time.zone.parse("2026-09-29T09:00:00-03:00"))
    expect(closed_task.reload.status).to eq("cancelada")
  end

  it "nao reabre visita cuja tarefa antiga ja foi concluida localmente" do
    lead = create(:lead, tenant:, admin_user: broker)
    task = create(:task, tenant:, lead:, admin_user: broker, status: "concluida")
    create_external_schedule_activity(lead:, task_id: task.id, external_key: "finished-visit", date: "2026-09-29T09:00:00-03:00", name: "Visita", alias_name: "scheduled_visit")
    described_class.call(tenant:, execute: true)
    expect(lead.appointments.sole.status).to eq("realizado")
  end

  it "separa IDs externos diferentes que foram importados na mesma tarefa" do
    lead = create(:lead, tenant:, admin_user: broker)
    task = create(:task, tenant:, lead:, admin_user: broker)
    first = create_external_schedule_activity(lead:, task_id: task.id, external_key: "one", date: "2026-09-29T09:00:00-03:00", name: "Retornar", alias_name: "feedback_customer")
    second = create_external_schedule_activity(lead:, task_id: task.id, external_key: "two", date: "2026-09-30T09:00:00-03:00", name: "Retornar", alias_name: "feedback_customer")
    described_class.call(tenant:, execute: true)
    expect(lead.tasks.reload.count).to eq(2)
    expect(first.reload.metadata["task_id"]).not_to eq(second.reload.metadata["task_id"])
    expect(described_class.call(tenant:, execute: false)).to have_attributes(tasks_updated: 0, tasks_created: 0)
  end

  it "usa o ultimo retrato de um mesmo ID externo e separa visitas diferentes" do
    lead = create(:lead, tenant:, admin_user: broker)
    appointment = create(:appointment, tenant:, lead:, admin_user: broker)
    first = create_external_schedule_activity(lead:, task_id: nil, external_key: "visit-one", date: "2026-09-29T09:00:00-03:00", name: "Visita", alias_name: "scheduled_visit")
    second = create_external_schedule_activity(lead:, task_id: nil, external_key: "visit-two", date: "2026-09-29T09:00:00-03:00", name: "Visita", alias_name: "scheduled_visit")
    [first, second].each { |activity| activity.update!(kind: "external_appointment", metadata: activity.metadata.merge("appointment_id" => appointment.id)) }
    latest = first.dup
    latest.metadata = first.metadata.deep_merge("raw" => { "status" => "Reagendada" })
    latest.save!
    second.update!(metadata: second.metadata.deep_merge("raw" => { "status" => "Realizada" }))
    described_class.call(tenant:, execute: true)
    expect(lead.appointments.reload.pluck(:status)).to contain_exactly("cancelado", "realizado")
    expect(described_class.call(tenant:, execute: false)).to have_attributes(appointments_updated: 0, appointments_created: 0, skipped: 1)
    integration = create(:external_lead_integration, tenant:)
    mapper = ExternalLeadMigration::LeadMapper.new("id" => "visit-identity", "attributes" => { "schedulated_actions" => [latest.reload.metadata["raw"]] })
    ExternalLeadMigration::LeadEnrichment.call(lead:, integration:, mapper:, historical: false)
    expect(lead.appointments.reload.pluck(:status)).to contain_exactly("cancelado", "realizado")
  end

  it "limita o backfill a integracao e rejeita tenant incompatível" do
    integration = create(:external_lead_integration, tenant:)
    lead = create(:lead, tenant:, admin_user: broker)
    create_external_schedule_activity(lead:, task_id: nil, external_key: "unrelated", date: "2026-09-29T09:00:00-03:00", name: "Retornar", alias_name: "feedback_customer")
    expect(described_class.call(integration:, execute: false).scanned).to eq(0)
    expect { described_class.call(tenant: Tenant.new(id: tenant.id + 1), integration:, execute: true) }.to raise_error(ArgumentError)
  end

  it "nao usa o usuario conector como fallback para agenda sem corretor mapeado" do
    connector = create(:admin_user, tenant:, email: "connector-c2s-reconcile@example.test")
    integration = create(:external_lead_integration, tenant:, connected_by_admin_user: connector, seller_mappings: {})
    lead = create(:lead, tenant:, external_lead_integration: integration, admin_user: nil, status: "Em Atendimento")
    create_external_schedule_activity(
      lead: lead,
      task_id: nil,
      external_key: "unmapped-return",
      date: "2026-08-20T09:00:00.000-03:00",
      name: "Retornar para o cliente",
      alias_name: "feedback_customer"
    )

    result = described_class.call(integration: integration, execute: true)

    expect(result).to have_attributes(scanned: 1, skipped: 1, tasks_created: 0)
    expect(lead.tasks).to be_empty
  end

  it "reatribui tarefa C2S existente para o responsavel atual do lead" do
    wrong_user = create(:admin_user, tenant:, email: "wrong-c2s-reconcile@example.test")
    lead = create(:lead, tenant:, admin_user: broker, status: "Em Atendimento")
    task = create(
      :task,
      tenant:,
      lead: lead,
      admin_user: wrong_user,
      title: "Ação agendada do legado",
      due_at: Time.zone.parse("2026-08-15T13:43:30-03:00")
    )
    create_external_schedule_activity(
      lead: lead,
      task_id: task.id,
      external_key: "wrong-owner-return",
      date: "2026-08-20T09:00:00.000-03:00",
      name: "Retornar para o cliente",
      alias_name: "feedback_customer"
    )

    result = described_class.call(tenant: tenant, execute: true, operational_only: true)

    expect(result).to have_attributes(scanned: 1, tasks_updated: 1, tasks_reassigned: 1)
    expect(task.reload.admin_user).to eq(broker)
  end

  it "pula leads sem corretor ativo no backfill operacional" do
    inactive = create(:admin_user, tenant:, active: false)
    [nil, inactive].each_with_index do |owner, index|
      lead = create(:lead, tenant:, admin_user: owner, status: "Em Atendimento")
      create_external_schedule_activity(lead:, task_id: nil, external_key: "inactive-#{index}", date: "2026-09-29T09:00:00-03:00", name: "Retornar", alias_name: "feedback_customer")
    end
    result = described_class.call(tenant:, execute: true, operational_only: true)
    expect(result).to have_attributes(scanned: 2, skipped_non_operational: 2, tasks_created: 0)
  end

  it "pula lead nao operacional quando o backfill roda em modo operacional" do
    pipeline = LeadPipeline.ensure_default!(tenant: tenant)
    closed_stage = tenant.lead_pipeline_stages.find_or_create_by!(lead_pipeline: pipeline, name: "Descartado") do |stage|
      stage.stage_type = "lost"
    end
    closed_stage.update!(stage_type: "lost") unless closed_stage.stage_type == "lost"
    lead = create(:lead, tenant:, admin_user: broker, lead_pipeline: pipeline, lead_pipeline_stage: closed_stage, status: closed_stage.name)
    task = create(
      :task,
      tenant:,
      lead: lead,
      admin_user: broker,
      title: "Ação agendada do legado",
      due_at: Time.zone.parse("2026-08-15T13:43:30-03:00")
    )
    create_external_schedule_activity(
      lead: lead,
      task_id: task.id,
      external_key: "closed-return",
      date: "2026-08-20T09:00:00.000-03:00",
      name: "Retornar para o cliente",
      alias_name: "feedback_customer"
    )

    result = described_class.call(tenant: tenant, execute: true, operational_only: true)

    expect(result).to have_attributes(scanned: 1, tasks_updated: 0, skipped_non_operational: 1)
    expect(task.reload.due_at).to eq(Time.zone.parse("2026-08-15T13:43:30-03:00"))
  end

  def create_external_schedule_activity(lead:, task_id:, external_key:, date:, name:, alias_name:)
    LeadActivity.log!(
      lead: lead,
      kind: "external_scheduled_action",
      metadata: {
        source: ExternalLeadMigration::LeadMapper::PROVIDER_KEY,
        external_key: external_key,
        task_id: task_id,
        raw: {
          id: external_key,
          status: "Em aberto",
          schedulated_action_date: date,
          schedulated_action_name: name,
          schedulated_action_type_alias: alias_name
        }
      }
    )
  end
end
