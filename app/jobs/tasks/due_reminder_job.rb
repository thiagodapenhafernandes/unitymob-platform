module Tasks
  class DueReminderJob < ApplicationJob
    queue_as :default

    BATCH_LIMIT = 200
    UPCOMING_LEAD_TIME = 30.minutes
    RETRY_ATTEMPT_AFTER = 30.minutes
    SENT_EVENT_TYPES = %w[provider_accepted device_received].freeze

    def perform(now: Time.current)
      Tenant.find_each do |tenant|
        Current.set(tenant: tenant) do
          due_tasks_for(tenant, now).find_each do |task|
            deliver_reminder(task, now)
          rescue => e
            Rails.logger.warn("[Tasks::DueReminderJob] falha na tarefa #{task.id}: #{e.class} #{e.message}")
          end
        end
      rescue => e
        Rails.logger.warn("[Tasks::DueReminderJob] falha ao varrer tenant #{tenant.id}: #{e.class} #{e.message}")
      end
    end

    private

    def due_tasks_for(tenant, now)
      tenant.tasks
            .pendentes
            .where.not(admin_user_id: nil, due_at: nil)
            .where("due_at <= ?", now + UPCOMING_LEAD_TIME)
            .joins(:admin_user)
            .merge(AdminUser.active)
            .includes(:admin_user, :lead)
            .limit(BATCH_LIMIT)
    end

    def deliver_reminder(task, now)
      phase = reminder_phase(task, now)
      return if phase.blank?
      return if reminder_sent?(task, phase)
      return if recent_attempt?(task, phase, now)

      lead = task.lead
      admin_user = task.admin_user
      return if admin_user.blank?
      return unless same_tenant?(task, lead, admin_user)

      Notifications::PushDispatcher.deliver(
        admin_user_id: admin_user.id,
        title: reminder_title(task, phase),
        body: reminder_body(task, lead, phase),
        url: reminder_url(task),
        tag: reminder_tag(task, phase),
        urgency: "high",
        ttl: 3600,
        require_interaction: true,
        lead_id: lead&.id,
        metadata: { task_id: task.id, source: "task_due_reminder", phase: phase }
      )
    end

    def reminder_phase(task, now)
      return "due" if task.due_at <= now
      return "upcoming" if task.due_at <= now + UPCOMING_LEAD_TIME

      nil
    end

    def reminder_sent?(task, phase)
      PushDeliveryEvent.where(tag: reminder_tag(task, phase), event_type: SENT_EVENT_TYPES).exists?
    end

    def recent_attempt?(task, phase, now)
      PushDeliveryEvent.where(tag: reminder_tag(task, phase))
                       .where("created_at >= ?", now - RETRY_ATTEMPT_AFTER)
                       .exists?
    end

    def reminder_tag(task, phase)
      return "task-return-#{task.id}" if phase == "due"

      "task-upcoming-#{task.id}"
    end

    def reminder_title(task, phase)
      prefix = phase == "upcoming" ? "Em breve: " : ""
      "#{prefix}#{task.title.presence || task.kind_label}"
    end

    def reminder_body(task, lead, phase)
      subject = lead&.display_name.presence || task.title.presence || "tarefa"
      time = I18n.l(task.due_at, format: "%d/%m/%Y às %H:%M")

      if phase == "upcoming"
        "Tarefa agendada para #{time}: #{subject}"
      else
        "Está na hora da tarefa: #{subject}"
      end
    end

    def reminder_url(task)
      task.lead_id.present? ? "/admin/leads/#{task.lead_id}" : "/admin/tasks"
    end

    def same_tenant?(task, lead, admin_user)
      task.tenant_id == admin_user.tenant_id && (lead.blank? || task.tenant_id == lead.tenant_id)
    end
  end
end
