module ExternalLeadMigration
  class ScheduledActionReconciler
    SOURCE = LeadMapper::PROVIDER_KEY
    Result = Struct.new(:scanned, :tasks_updated, :tasks_created, :appointments_updated, :appointments_created, :tasks_cancelled, :skipped, keyword_init: true)

    def self.call(tenant: nil, integration: nil, execute: false)
      new(tenant:, integration:, execute:).call
    end

    def initialize(tenant: nil, integration: nil, execute: false)
      @tenant = integration&.tenant || tenant
      @integration = integration
      @execute = execute
      @result = Result.new(scanned: 0, tasks_updated: 0, tasks_created: 0, appointments_updated: 0, appointments_created: 0, tasks_cancelled: 0, skipped: 0)
    end

    def call
      scheduled_activities.find_each(batch_size: 500) do |activity|
        result.scanned += 1
        reconcile_activity(activity)
      end

      result
    end

    private

    attr_reader :tenant, :integration, :execute, :result

    def scheduled_activities
      scope = LeadActivity
              .includes(:lead)
              .where(kind: "external_scheduled_action")
              .where("metadata @> ?", { source: SOURCE }.to_json)
      scope = scope.where(tenant_id: tenant.id) if tenant.present?
      return scope if integration.blank?

      scope.joins(:lead).where(leads: { tenant_id: integration.tenant_id })
    end

    def reconcile_activity(activity)
      lead = activity.lead
      action = scheduled_action_from(activity)
      return skip! if lead.blank? || action[:due_at].blank? || action[:admin_user].blank?

      action[:visit] ? reconcile_appointment(activity, lead, action) : reconcile_task(activity, lead, action)
    end

    def reconcile_task(activity, lead, action)
      task = task_for(activity, lead, action)
      task_new = task.new_record?

      if execute
        task.assign_attributes(
          tenant: lead.tenant,
          lead: lead,
          admin_user: action[:admin_user],
          created_by: integration&.connected_by_admin_user || task.created_by,
          title: action[:title],
          kind: action[:kind],
          due_at: action[:due_at],
          status: action[:status],
          completed_at: action[:status] == "concluida" ? action[:due_at] : nil,
          priority: task.priority.presence || "normal",
          description: action[:description]
        )
        task.save!
      end

      task_new ? result.tasks_created += 1 : result.tasks_updated += 1
    end

    def reconcile_appointment(activity, lead, action)
      appointment = appointment_for(activity, lead, action)
      appointment_new = appointment.new_record?

      if execute
        appointment.assign_attributes(
          tenant: lead.tenant,
          lead: lead,
          admin_user: action[:admin_user],
          habitation_id: lead.property_id,
          title: action[:title],
          kind: action[:appointment_kind],
          starts_at: action[:due_at],
          status: appointment_status_from(action[:status]),
          notes: action[:description]
        )
        appointment.save!
        cancel_legacy_task!(activity, lead) if legacy_task_for(activity, lead).present?
      end

      appointment_new ? result.appointments_created += 1 : result.appointments_updated += 1
    end

    def task_for(activity, lead, action)
      legacy_task_for(activity, lead) ||
        lead.tasks.find_or_initialize_by(
          admin_user: action[:admin_user],
          title: action[:title],
          due_at: action[:due_at]
        )
    end

    def appointment_for(activity, lead, action)
      appointment_id = activity.metadata["appointment_id"]
      return lead.appointments.find_by(id: appointment_id) if appointment_id.present? && lead.appointments.exists?(id: appointment_id)

      lead.appointments.find_or_initialize_by(
        admin_user: action[:admin_user],
        title: action[:title],
        starts_at: action[:due_at]
      )
    end

    def legacy_task_for(activity, lead)
      task_id = activity.metadata["task_id"]
      return nil if task_id.blank?

      lead.tasks.find_by(id: task_id)
    end

    def cancel_legacy_task!(activity, lead)
      task = legacy_task_for(activity, lead)
      return if task.blank? || task.status == "cancelada"

      task.update!(status: "cancelada")
      result.tasks_cancelled += 1
    end

    def scheduled_action_from(activity)
      raw = activity.metadata["raw"].presence || {}
      title = raw["schedulated_action_name"].presence ||
        raw["name"].presence ||
        raw["title"].presence ||
        activity.metadata["title"].presence ||
        "Ação agendada"
      due_at = parse_time(
        raw["schedulated_action_date"].presence ||
          raw["due_at"].presence ||
          raw["scheduled_at"].presence ||
          raw["date"].presence ||
          raw["datetime"].presence ||
          activity.metadata["due_at"]
      )
      text = [
        raw["schedulated_action_name"],
        raw["schedulated_action_type_alias"],
        raw["name"],
        raw["title"],
        raw["alias"],
        raw["type"],
        activity.metadata["title"]
      ].compact.join(" ").parameterize(separator: "_")
      status = task_status(raw)

      {
        admin_user: responsible_user(activity.lead, raw),
        appointment_kind: appointment_kind(text),
        description: raw["description"].presence || raw["observation"].presence || raw["note"].presence,
        due_at: due_at,
        kind: task_kind(text),
        status: status,
        title: title,
        visit: text.include?("visita") || text.include?("scheduled_visit") || text.include?("reuniao")
      }
    end

    def responsible_user(lead, raw)
      lead&.admin_user ||
        AdminUser.find_by(id: raw["seller_id"]) ||
        integration&.connected_by_admin_user
    end

    def task_kind(text)
      return "ligacao" if text.include?("ligacao") || text.include?("call")
      return "visita" if text.include?("visita")
      return "email" if text.include?("email")

      "follow_up"
    end

    def appointment_kind(text)
      return "reuniao" if text.include?("reuniao")
      return "ligacao" if text.include?("ligacao")

      "visita"
    end

    def task_status(raw)
      status = [raw["status"], raw["status_name"], raw["done"]].compact.join(" ").parameterize(separator: "_")
      return "concluida" if status.include?("finalizado") || status.include?("concluido") || status == "true"
      return "cancelada" if status.include?("cancel")

      "pendente"
    end

    def appointment_status_from(task_status)
      return "realizado" if task_status == "concluida"
      return "cancelado" if task_status == "cancelada"

      "agendado"
    end

    def parse_time(value)
      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def skip!
      result.skipped += 1
    end
  end
end
