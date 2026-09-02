module Appointments
  class DueReminderJob < ApplicationJob
    queue_as :default

    BATCH_LIMIT = 200
    UPCOMING_LEAD_TIME = 1.hour
    UPCOMING_PHASES = {
      "15_minutes_before" => 15.minutes,
      "30_minutes_before" => 30.minutes,
      "1_hour_before" => 1.hour
    }.freeze
    OVERDUE_REPEAT_INTERVAL = 2.hours
    BUSINESS_HOURS = 8...18
    RETRY_ATTEMPT_AFTER = 30.minutes
    SENT_EVENT_TYPES = %w[provider_accepted device_received].freeze

    def perform(now: Time.current)
      Tenant.find_each do |tenant|
        Current.set(tenant: tenant) do
          due_appointments_for(tenant, now).find_each do |appointment|
            deliver_reminder(appointment, now)
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
            .where("starts_at <= ?", now + UPCOMING_LEAD_TIME)
            .joins(:admin_user)
            .merge(AdminUser.active)
            .includes(:admin_user, :lead, :habitation)
            .limit(BATCH_LIMIT)
    end

    def deliver_reminder(appointment, now)
      phase = reminder_phase(appointment, now)
      phase = overdue_phase(appointment, now) if phase == "due" && (reminder_sent?(appointment, "due", now) || appointment.starts_at <= now - OVERDUE_REPEAT_INTERVAL)
      return if phase.blank?
      return if reminder_sent?(appointment, phase, now)
      return if recent_attempt?(appointment, phase, now)

      admin_user = appointment.admin_user
      return if admin_user.blank?
      return unless same_tenant?(appointment, admin_user)

      Notifications::PushDispatcher.deliver(
        admin_user_id: admin_user.id,
        title: reminder_title(appointment, phase),
        body: reminder_body(appointment, phase),
        url: reminder_url(appointment),
        tag: reminder_tag(appointment, phase, now),
        urgency: "high",
        ttl: 3600,
        require_interaction: true,
        lead_id: appointment.lead_id,
        metadata: { appointment_id: appointment.id, source: "appointment_due_reminder", phase: phase }
      )
    end

    def reminder_phase(appointment, now)
      return "due" if appointment.starts_at <= now

      UPCOMING_PHASES.each do |phase, lead_time|
        return phase if appointment.starts_at <= now + lead_time
      end

      nil
    end

    def reminder_sent?(appointment, phase, now = Time.current)
      PushDeliveryEvent.where(tag: reminder_tag(appointment, phase, now), event_type: SENT_EVENT_TYPES).exists?
    end

    def recent_attempt?(appointment, phase, now)
      PushDeliveryEvent.where(tag: reminder_tag(appointment, phase, now))
                       .where("created_at >= ?", now - RETRY_ATTEMPT_AFTER)
                       .exists?
    end

    def reminder_tag(appointment, phase, now = Time.current)
      return "appointment-overdue-#{appointment.id}-#{overdue_bucket(now)}" if phase == "overdue"

      "appointment-#{phase}-#{appointment.id}"
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
      when "1_hour_before"
        "Falta 1 hora para o compromisso: #{subject}. Horário: #{time}."
      when "30_minutes_before"
        "Faltam 30 minutos para o compromisso: #{subject}. Horário: #{time}."
      when "15_minutes_before"
        "Faltam 15 minutos para o compromisso: #{subject}. Horário: #{time}."
      when "overdue"
        "Esse compromisso está vencido: #{subject}. Marque como realizado ou cancele quando resolver."
      else
        "Está na hora do compromisso: #{subject}"
      end
    end

    def overdue_phase(appointment, now)
      return nil if appointment.starts_at > now - OVERDUE_REPEAT_INTERVAL
      return nil unless business_hours?(now)

      "overdue"
    end

    def business_hours?(time)
      BUSINESS_HOURS.cover?(time.in_time_zone.hour)
    end

    def overdue_bucket(time)
      (time.to_i / OVERDUE_REPEAT_INTERVAL.to_i)
    end

    def reminder_url(appointment)
      appointment.lead_id.present? ? "/admin/leads/#{appointment.lead_id}" : "/admin/appointments"
    end

    def same_tenant?(appointment, admin_user)
      return false unless appointment.tenant_id == admin_user.tenant_id
      return false if appointment.lead.present? && appointment.lead.tenant_id != appointment.tenant_id
      return false if appointment.habitation.present? && appointment.habitation.tenant_id != appointment.tenant_id

      true
    end
  end
end
