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
