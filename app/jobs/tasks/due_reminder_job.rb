module Tasks
  class DueReminderJob < ApplicationJob
    queue_as :default

    BATCH_LIMIT = 200
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
            .where(kind: "follow_up")
            .where.not(lead_id: nil, admin_user_id: nil, due_at: nil)
            .where("due_at <= ?", now)
            .joins(:admin_user, :lead)
            .merge(AdminUser.active)
            .includes(:admin_user, :lead)
            .limit(BATCH_LIMIT)
    end

    def deliver_reminder(task, now)
      return if reminder_sent?(task)
      return if recent_attempt?(task, now)

      lead = task.lead
      admin_user = task.admin_user
      return if lead.blank? || admin_user.blank?
      return unless same_tenant?(task, lead, admin_user)

      Notifications::PushDispatcher.deliver(
        admin_user_id: admin_user.id,
        title: task.title.presence || "Retornar para o cliente",
        body: reminder_body(lead),
        url: "/admin/leads/#{lead.id}",
        tag: reminder_tag(task),
        urgency: "high",
        ttl: 3600,
        require_interaction: true,
        lead_id: lead.id,
        metadata: { task_id: task.id, source: "task_due_reminder" }
      )
    end

    def reminder_sent?(task)
      PushDeliveryEvent.where(tag: reminder_tag(task), event_type: SENT_EVENT_TYPES).exists?
    end

    def recent_attempt?(task, now)
      PushDeliveryEvent.where(tag: reminder_tag(task))
                       .where("created_at >= ?", now - RETRY_ATTEMPT_AFTER)
                       .exists?
    end

    def reminder_tag(task)
      "task-return-#{task.id}"
    end

    def reminder_body(lead)
      name = lead.display_name.presence || lead.name.presence || "cliente"
      "Está na hora de retornar para o cliente -> #{name}"
    end

    def same_tenant?(task, lead, admin_user)
      task.tenant_id == lead.tenant_id && task.tenant_id == admin_user.tenant_id
    end
  end
end
