module Tasks
  class DueReminderJob < ApplicationJob
    queue_as :default

    BATCH_SIZE = 200

    def perform(now: nil)
      Tenant.find_each(batch_size: BATCH_SIZE) do |tenant|
        Current.set(tenant: tenant) do
          @reminder_setting = LeadSetting.instance(tenant: tenant)
          due_tasks_for(tenant, now || Time.current).find_each(batch_size: BATCH_SIZE) do |task|
            deliver_reminder(task, now || Time.current)
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
            .operational_current
            .pendentes
            .where.not(admin_user_id: nil, due_at: nil)
            .where("due_at <= ?", now + @reminder_setting.reminder_first_minutes.minutes)
            .joins(:admin_user)
            .merge(AdminUser.active)
            .includes(:admin_user, :lead)
    end

    def reminder_title(task, phase)
      prefix = phase.start_with?("1_hour", "30_minutes", "15_minutes") ? "Em breve: " : ""
      "#{prefix}#{task.title.presence || task.kind_label}"
    end

    def reminder_body(task, lead, phase)
      subject = lead&.display_name.presence || task.title.presence || "tarefa"
      time = I18n.l(task.due_at, format: "%d/%m/%Y às %H:%M")

      case phase
      when *@reminder_setting.reminder_phases.keys
        minutes = (@reminder_setting.reminder_phases.fetch(phase) / 60).to_i
        anticipation = { 1 => "Falta 1 minuto", 60 => "Falta 1 hora" }.fetch(minutes) { "Faltam #{minutes} minutos" }
        "#{anticipation} para a tarefa: #{subject}. Horário: #{time}."
      when "overdue"
        "Essa tarefa está vencida: #{subject}. Conclua ou cancele quando resolver."
      else
        "Está na hora da tarefa: #{subject}"
      end
    end

    def deliver_reminder(task, now)
      Activities::ReminderDelivery.new(task, setting: @reminder_setting, now: now).call do |phase, tag|
        Notifications::PushDispatcher.deliver(
          admin_user_id: task.admin_user_id,
          title: reminder_title(task, phase),
          body: reminder_body(task, task.lead, phase),
          url: reminder_url(task),
          tag: tag,
          urgency: "high",
          ttl: 3600,
          require_interaction: true,
          lead_id: task.lead_id,
          metadata: { task_id: task.id, source: "task_due_reminder", phase: phase }
        )
      end
    end

    def reminder_url(task)
      task.lead_id.present? ? "/admin/leads/#{task.lead_id}" : "/admin/tasks"
    end
  end
end
