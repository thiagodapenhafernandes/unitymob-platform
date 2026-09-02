require "rails_helper"

RSpec.describe Tasks::DueReminderJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  let(:tenant) { Tenant.create!(name: "Tenant retorno #{SecureRandom.hex(3)}", slug: "tenant-retorno-#{SecureRandom.hex(3)}") }
  let(:profile) { tenant.profiles.find_by!(key: "agent") }
  let(:broker) { create(:admin_user, tenant: tenant, profile: profile, email: "retorno-#{SecureRandom.hex(6)}@example.com") }
  let(:lead) { create(:lead, tenant: tenant, admin_user: broker, name: "Gilson") }

  around do |example|
    travel_to(Time.zone.local(2026, 8, 19, 9, 30)) { example.run }
  end

  before do
    lead
    allow(Tenant).to receive(:find_each).and_yield(tenant)
    allow(Notifications::PushDispatcher).to receive(:deliver).and_return(1)
  end

  it "envia push para tarefa vencida do corretor responsavel" do
    task = create(:task, tenant: tenant, lead: lead, admin_user: broker, due_at: 5.minutes.ago)

    described_class.perform_now

    expect(Notifications::PushDispatcher).to have_received(:deliver).with(
      admin_user_id: broker.id,
      title: "Retornar para o cliente",
      body: "Está na hora da tarefa: Gilson",
      url: "/admin/leads/#{lead.id}",
      tag: "task-return-#{task.id}",
      urgency: "high",
      ttl: 3600,
      require_interaction: true,
      lead_id: lead.id,
      metadata: { task_id: task.id, source: "task_due_reminder", phase: "due" }
    )
  end

  it "envia push trinta minutos antes da tarefa vencer" do
    task = create(:task, tenant: tenant, lead: lead, admin_user: broker, kind: "ligacao", title: "Ligar para confirmar visita", due_at: 20.minutes.from_now)

    described_class.perform_now

    expect(Notifications::PushDispatcher).to have_received(:deliver).with(
      admin_user_id: broker.id,
      title: "Em breve: Ligar para confirmar visita",
      body: "Faltam 30 minutos para a tarefa: Gilson. Horário: 19/08/2026 às 09:50.",
      url: "/admin/leads/#{lead.id}",
      tag: "task-30_minutes_before-#{task.id}",
      urgency: "high",
      ttl: 3600,
      require_interaction: true,
      lead_id: lead.id,
      metadata: { task_id: task.id, source: "task_due_reminder", phase: "30_minutes_before" }
    )
  end

  it "nao reenvia quando o provedor ja aceitou o lembrete da tarefa" do
    task = create(:task, tenant: tenant, lead: lead, admin_user: broker, due_at: 5.minutes.ago)
    PushDeliveryEvent.create!(
      admin_user: broker,
      lead: lead,
      event_type: "provider_accepted",
      tag: "task-return-#{task.id}",
      metadata: { task_id: task.id }
    )

    described_class.perform_now

    expect(Notifications::PushDispatcher).not_to have_received(:deliver)
  end

  it "segura novas tentativas por trinta minutos quando acabou de tentar sem subscription" do
    task = create(:task, tenant: tenant, lead: lead, admin_user: broker, due_at: 5.minutes.ago)
    PushDeliveryEvent.create!(
      admin_user: broker,
      lead: lead,
      event_type: "no_active_subscription",
      tag: "task-return-#{task.id}",
      created_at: 10.minutes.ago,
      updated_at: 10.minutes.ago,
      metadata: { task_id: task.id }
    )

    described_class.perform_now

    expect(Notifications::PushDispatcher).not_to have_received(:deliver)
  end

  it "ignora tarefas muito futuras e concluidas" do
    create(:task, tenant: tenant, lead: lead, admin_user: broker, due_at: 61.minutes.from_now)
    create(:task, tenant: tenant, lead: lead, admin_user: broker, status: "concluida", due_at: 5.minutes.ago)

    described_class.perform_now

    expect(Notifications::PushDispatcher).not_to have_received(:deliver)
  end

  it "notifica tarefa sem lead usando a tela de tarefas" do
    task = create(:task, tenant: tenant, lead: nil, admin_user: broker, title: "Cobrar documento", due_at: 5.minutes.ago)

    described_class.perform_now

    expect(Notifications::PushDispatcher).to have_received(:deliver).with(hash_including(
      admin_user_id: broker.id,
      body: "Está na hora da tarefa: Cobrar documento",
      url: "/admin/tasks",
      tag: "task-return-#{task.id}",
      lead_id: nil,
      metadata: { task_id: task.id, source: "task_due_reminder", phase: "due" }
    ))
  end

  it "ignora responsavel inativo" do
    broker.update!(active: false)
    create(:task, tenant: tenant, lead: lead, admin_user: broker, due_at: 5.minutes.ago)

    described_class.perform_now

    expect(Notifications::PushDispatcher).not_to have_received(:deliver)
  end

  it "repete tarefa vencida de duas em duas horas durante horario comercial" do
    task = create(:task, tenant: tenant, lead: lead, admin_user: broker, due_at: 3.hours.ago)
    PushDeliveryEvent.create!(
      admin_user: broker,
      lead: lead,
      event_type: "provider_accepted",
      tag: "task-return-#{task.id}",
      metadata: { task_id: task.id }
    )

    described_class.perform_now

    expect(Notifications::PushDispatcher).to have_received(:deliver).with(hash_including(
      admin_user_id: broker.id,
      body: "Essa tarefa está vencida: Gilson. Conclua ou cancele quando resolver.",
      tag: "task-overdue-#{task.id}-#{Time.current.to_i / 2.hours.to_i}",
      metadata: { task_id: task.id, source: "task_due_reminder", phase: "overdue" }
    ))
  end

  it "nao repete tarefa vencida fora do horario comercial" do
    now = Time.zone.local(2026, 8, 19, 20, 0)
    task = create(:task, tenant: tenant, lead: lead, admin_user: broker, due_at: now - 3.hours)
    PushDeliveryEvent.create!(
      admin_user: broker,
      lead: lead,
      event_type: "provider_accepted",
      tag: "task-return-#{task.id}",
      metadata: { task_id: task.id }
    )

    described_class.perform_now(now: now)

    expect(Notifications::PushDispatcher).not_to have_received(:deliver)
  end
end
