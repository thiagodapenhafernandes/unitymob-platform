module Appointments
  class DueReminderJob < ApplicationJob
    queue_as :default

    BATCH_SIZE = 200

    def perform(now: nil)
      Tenant.find_each(batch_size: BATCH_SIZE) do |tenant|
        Current.set(tenant: tenant) do
          @reminder_setting = LeadSetting.instance(tenant: tenant)
          due_appointments_for(tenant, now || Time.current).find_each(batch_size: BATCH_SIZE) do |appointment|
            deliver_reminder(appointment, now || Time.current)
          rescue => e
            Rails.logger.warn("[Appointments::DueReminderJob] falha no compromisso #{appointment.id}: #{e.class} #{e.message}")
          end
        end
      rescue => e
        Rails.logger.warn("[Appointments::DueReminderJob] falha ao varrer tenant #{tenant.id}: #{e.class} #{e.message}")
      end
    end

    private

    def due_appointments_for(tenant, now)
      tenant.appointments
            .where(status: "agendado")
            .where.not(admin_user_id: nil, starts_at: nil)
            .where("starts_at <= ?", now + @reminder_setting.reminder_first_minutes.minutes)
            .joins(:admin_user)
            .merge(AdminUser.active)
            .includes(:admin_user, :lead, :habitation)
    end

    def deliver_reminder(appointment, now)
      Activities::ReminderDelivery.new(appointment, setting: @reminder_setting, now: now).call do |phase, tag|
        Notifications::PushDispatcher.deliver(
          admin_user_id: appointment.admin_user_id,
          title: reminder_title(appointment, phase),
          body: reminder_body(appointment, phase),
          url: reminder_url(appointment),
          tag: tag,
          urgency: "high",
          ttl: 3600,
          require_interaction: true,
          lead_id: appointment.lead_id,
          metadata: { appointment_id: appointment.id, source: "appointment_due_reminder", phase: phase }
        )
      end
    end

    def reminder_title(appointment, phase)
      prefix = phase.start_with?("1_hour", "30_minutes", "15_minutes") ? "Em breve: " : ""
      "#{prefix}#{appointment.title.presence || appointment.kind_label}"
    end

    def reminder_body(appointment, phase)
      time = I18n.l(appointment.starts_at, format: "%d/%m/%Y às %H:%M")
      subject = [
        appointment.lead&.display_name.presence,
        appointment.habitation&.display_title.presence,
        appointment.location.presence
      ].compact_blank.first || appointment.kind_label

      case phase
      when *@reminder_setting.reminder_phases.keys
        minutes = (@reminder_setting.reminder_phases.fetch(phase) / 60).to_i
        anticipation = { 1 => "Falta 1 minuto", 60 => "Falta 1 hora" }.fetch(minutes) { "Faltam #{minutes} minutos" }
        "#{anticipation} para o compromisso: #{subject}. Horário: #{time}."
      when "overdue"
        "Esse compromisso está vencido: #{subject}. Marque como realizado ou cancele quando resolver."
      else
        "Está na hora do compromisso: #{subject}"
      end
    end

    def reminder_url(appointment)
      appointment.lead_id.present? ? "/admin/leads/#{appointment.lead_id}" : "/admin/appointments"
    end
  end
end
