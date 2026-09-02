require "rails_helper"

RSpec.describe Appointments::DueReminderJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  let(:tenant) { Tenant.create!(name: "Tenant agenda #{SecureRandom.hex(3)}", slug: "tenant-agenda-#{SecureRandom.hex(3)}") }
  let(:profile) { tenant.profiles.find_by!(key: "agent") }
  let(:broker) { create(:admin_user, tenant: tenant, profile: profile, email: "agenda-#{SecureRandom.hex(6)}@example.com") }
  let(:lead) { create(:lead, tenant: tenant, admin_user: broker, name: "Marina") }

  around do |example|
    travel_to(Time.zone.local(2026, 8, 19, 9, 30)) { example.run }
  end

  before do
    lead
    allow(Tenant).to receive(:find_each).and_yield(tenant)
    allow(Notifications::PushDispatcher).to receive(:deliver).and_return(1)
  end

  it "envia push trinta minutos antes do compromisso iniciar" do
    appointment = create(:appointment, tenant: tenant, lead: lead, admin_user: broker, title: "Visita no Centro", starts_at: 20.minutes.from_now)

    described_class.perform_now

    expect(Notifications::PushDispatcher).to have_received(:deliver).with(
      admin_user_id: broker.id,
      title: "Em breve: Visita no Centro",
      body: "Faltam 30 minutos para o compromisso: Marina. Horário: 19/08/2026 às 09:50.",
      url: "/admin/leads/#{lead.id}",
      tag: "appointment-30_minutes_before-#{appointment.id}",
      urgency: "high",
      ttl: 3600,
      require_interaction: true,
      lead_id: lead.id,
      metadata: { appointment_id: appointment.id, source: "appointment_due_reminder", phase: "30_minutes_before" }
    )
  end

  it "envia push quando o compromisso chega no horario" do
    appointment = create(:appointment, tenant: tenant, lead: lead, admin_user: broker, title: "Ligação com cliente", kind: "ligacao", starts_at: 2.minutes.ago)

    described_class.perform_now

    expect(Notifications::PushDispatcher).to have_received(:deliver).with(hash_including(
      admin_user_id: broker.id,
      title: "Ligação com cliente",
      body: "Está na hora do compromisso: Marina",
      url: "/admin/leads/#{lead.id}",
      tag: "appointment-due-#{appointment.id}",
      lead_id: lead.id,
      metadata: { appointment_id: appointment.id, source: "appointment_due_reminder", phase: "due" }
    ))
  end

  it "notifica compromisso sem lead usando a agenda" do
    appointment = create(:appointment, tenant: tenant, lead: nil, admin_user: broker, title: "Reunião interna", kind: "reuniao", starts_at: 5.minutes.ago)

    described_class.perform_now

    expect(Notifications::PushDispatcher).to have_received(:deliver).with(hash_including(
      admin_user_id: broker.id,
      body: "Está na hora do compromisso: Reunião",
      url: "/admin/appointments",
      tag: "appointment-due-#{appointment.id}",
      lead_id: nil
    ))
  end

  it "nao reenvia quando o provedor ja aceitou o lembrete da agenda" do
    appointment = create(:appointment, tenant: tenant, lead: lead, admin_user: broker, starts_at: 10.minutes.from_now)
    PushDeliveryEvent.create!(
      admin_user: broker,
      lead: lead,
      event_type: "provider_accepted",
      tag: "appointment-15_minutes_before-#{appointment.id}",
      metadata: { appointment_id: appointment.id }
    )

    described_class.perform_now

    expect(Notifications::PushDispatcher).not_to have_received(:deliver)
  end

  it "ignora compromisso muito futuro, cancelado e responsavel inativo" do
    create(:appointment, tenant: tenant, lead: lead, admin_user: broker, starts_at: 61.minutes.from_now)
    create(:appointment, tenant: tenant, lead: lead, admin_user: broker, status: "cancelado", starts_at: 5.minutes.ago)
    broker.update!(active: false)
    create(:appointment, tenant: tenant, lead: lead, admin_user: broker, starts_at: 5.minutes.ago)

    described_class.perform_now

    expect(Notifications::PushDispatcher).not_to have_received(:deliver)
  end

  it "repete compromisso vencido de duas em duas horas durante horario comercial" do
    appointment = create(:appointment, tenant: tenant, lead: lead, admin_user: broker, starts_at: 3.hours.ago)
    PushDeliveryEvent.create!(
      admin_user: broker,
      lead: lead,
      event_type: "provider_accepted",
      tag: "appointment-due-#{appointment.id}",
      metadata: { appointment_id: appointment.id }
    )

    described_class.perform_now

    expect(Notifications::PushDispatcher).to have_received(:deliver).with(hash_including(
      admin_user_id: broker.id,
      body: "Esse compromisso está vencido: Marina. Marque como realizado ou cancele quando resolver.",
      tag: "appointment-overdue-#{appointment.id}-#{Time.current.to_i / 2.hours.to_i}",
      metadata: { appointment_id: appointment.id, source: "appointment_due_reminder", phase: "overdue" }
    ))
  end

  it "nao repete compromisso vencido fora do horario comercial" do
    now = Time.zone.local(2026, 8, 19, 20, 0)
    appointment = create(:appointment, tenant: tenant, lead: lead, admin_user: broker, starts_at: now - 3.hours)
    PushDeliveryEvent.create!(
      admin_user: broker,
      lead: lead,
      event_type: "provider_accepted",
      tag: "appointment-due-#{appointment.id}",
      metadata: { appointment_id: appointment.id }
    )

    described_class.perform_now(now: now)

    expect(Notifications::PushDispatcher).not_to have_received(:deliver)
  end
end
