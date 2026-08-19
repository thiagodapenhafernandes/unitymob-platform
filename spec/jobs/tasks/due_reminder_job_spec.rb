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

  it "envia push para retorno vencido do corretor responsavel" do
    task = create(:task, tenant: tenant, lead: lead, admin_user: broker, due_at: 5.minutes.ago)

    described_class.perform_now

    expect(Notifications::PushDispatcher).to have_received(:deliver).with(
      admin_user_id: broker.id,
      title: "Retornar para o cliente",
      body: "Está na hora de retornar para o cliente -> Gilson",
      url: "/admin/leads/#{lead.id}",
      tag: "task-return-#{task.id}",
      urgency: "high",
      ttl: 3600,
      require_interaction: true,
      lead_id: lead.id,
      metadata: { task_id: task.id, source: "task_due_reminder" }
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

  it "ignora tarefas futuras, concluidas, sem lead e de outro tipo" do
    create(:task, tenant: tenant, lead: lead, admin_user: broker, due_at: 5.minutes.from_now)
    create(:task, tenant: tenant, lead: lead, admin_user: broker, status: "concluida", due_at: 5.minutes.ago)
    create(:task, tenant: tenant, lead: nil, admin_user: broker, due_at: 5.minutes.ago)
    create(:task, tenant: tenant, lead: lead, admin_user: broker, kind: "ligacao", due_at: 5.minutes.ago)

    described_class.perform_now

    expect(Notifications::PushDispatcher).not_to have_received(:deliver)
  end

  it "ignora responsavel inativo" do
    broker.update!(active: false)
    create(:task, tenant: tenant, lead: lead, admin_user: broker, due_at: 5.minutes.ago)

    described_class.perform_now

    expect(Notifications::PushDispatcher).not_to have_received(:deliver)
  end
end
