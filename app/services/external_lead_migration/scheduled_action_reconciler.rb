module ExternalLeadMigration
  class ScheduledActionReconciler
    SOURCE = LeadMapper::PROVIDER_KEY
    Result = Struct.new(
      :scanned,
      :tasks_updated,
      :tasks_created,
      :tasks_reassigned,
      :appointments_updated,
      :appointments_created,
      :appointments_reassigned,
      :tasks_cancelled,
      :skipped,
      :skipped_non_operational,
      keyword_init: true
    )

    def self.call(tenant: nil, integration: nil, execute: false, operational_only: false)
      new(tenant:, integration:, execute:, operational_only:).call
    end

    def initialize(tenant: nil, integration: nil, execute: false, operational_only: false)
      raise ArgumentError, "Integração não pertence ao tenant informado" if tenant && integration && tenant.id != integration.tenant_id
      @tenant = integration&.tenant || tenant
      @integration = integration
      @execute = execute
      @operational_only = operational_only
      @result = Result.new(
        scanned: 0,
        tasks_updated: 0,
        tasks_created: 0,
        tasks_reassigned: 0,
        appointments_updated: 0,
        appointments_created: 0,
        appointments_reassigned: 0,
        tasks_cancelled: 0,
        skipped: 0,
        skipped_non_operational: 0
      )
    end

    def call
      prepare_identity_index
      scheduled_activities.find_each(batch_size: 500) do |activity|
        result.scanned += 1
        Current.set(tenant: tenant || activity.lead&.tenant) do
          if execute
            activity.with_lock { reconcile_activity(activity) }
          else
            reconcile_activity(activity)
          end
        end
      end

      result
    end

    private

    attr_reader :tenant, :integration, :execute, :operational_only, :result

    def scheduled_activities
      scope = LeadActivity
              .includes(lead: [:tenant, :admin_user])
              .where(kind: %w[external_scheduled_action external_appointment])
              .where("metadata @> ?", { source: SOURCE }.to_json)
      scope = scope.where(tenant_id: tenant.id) if tenant.present?
      return scope if integration.blank?

      scope.joins(:lead).where(leads: { tenant_id: integration.tenant_id, external_lead_integration_id: integration.id })
    end

    def reconcile_activity(activity)
      lead = activity.lead
      return skip_non_operational! if operational_only && !operational_lead?(lead)
      return skip! unless @canonical_activity_ids[activity.id]

      action = scheduled_action_from(activity)
      return skip! if lead.blank? || action[:due_at].blank? || action[:admin_user].blank?

      action[:visit] ? reconcile_appointment(activity, lead, action) : reconcile_task(activity, lead, action)
    end

    def reconcile_task(activity, lead, action)
      task = task_for(activity, lead, action)
      task_new = task.new_record?
      previous_admin_user_id = task.admin_user_id
      status = action[:status]
      status = task.status if task.persisted? && task.status.in?(%w[concluida cancelada]) && status == "pendente"

      task.assign_attributes(
        tenant: lead.tenant,
        lead: lead,
        admin_user: action[:admin_user],
        created_by_id: task.created_by_id || integration&.connected_by_admin_user_id,
        title: action[:title],
        kind: action[:kind],
        due_at: action[:due_at],
        status: status,
        completed_at: status == "concluida" ? (task.completed_at || action[:due_at]) : nil,
        source: "external_legacy",
        priority: task.priority.presence || "normal",
        description: action[:description]
      )
      changed = task.changed?
      if execute
        task.save! if changed
        update_activity!(activity, task_id: task.id, title: task.title, due_at: task.due_at.iso8601)
      end

      result.tasks_reassigned += 1 if previous_admin_user_id.present? && previous_admin_user_id != action[:admin_user].id
      task_new ? result.tasks_created += 1 : result.tasks_updated += 1 if changed
    end

    def reconcile_appointment(activity, lead, action)
      appointment = appointment_for(activity, lead, action)
      appointment_new = appointment.new_record?
      previous_admin_user_id = appointment.admin_user_id
      status = appointment_status_from(action[:status])
      status = appointment.status if appointment.persisted? && appointment.status.in?(%w[realizado cancelado]) && status == "agendado"
      if appointment_new && status == "agendado"
        legacy_status = legacy_task_for(activity, lead)&.status
        status = appointment_status_from(legacy_status) if legacy_status.in?(%w[concluida cancelada])
      end

      appointment.assign_attributes(
        tenant: lead.tenant,
        lead: lead,
        admin_user: action[:admin_user],
        habitation_id: lead.property_id,
        title: action[:title],
        kind: action[:appointment_kind],
        starts_at: action[:due_at],
        status: status,
        notes: action[:description]
      )
      changed = appointment.changed?
      if execute
        appointment.save! if changed
        update_activity!(activity, appointment_id: appointment.id, title: appointment.title, starts_at: appointment.starts_at.iso8601)
      end
      cancel_legacy_task!(activity, lead)

      result.appointments_reassigned += 1 if previous_admin_user_id.present? && previous_admin_user_id != action[:admin_user].id
      appointment_new ? result.appointments_created += 1 : result.appointments_updated += 1 if changed
    end

    def task_for(activity, lead, action)
      task = legacy_task_for(activity, lead)
      return shared_record?(activity, lead, "task_id", task.id) ? task.dup : task if task
      return lead.tasks.new if activity.metadata["external_key"].present?

        lead.tasks.find_or_initialize_by(
          admin_user: action[:admin_user],
          title: action[:title],
          due_at: action[:due_at]
        )
    end

    def appointment_for(activity, lead, action)
      appointment_id = activity.metadata["appointment_id"]
      appointment = lead.appointments.find_by(id: appointment_id) if appointment_id.present?
      return shared_record?(activity, lead, "appointment_id", appointment.id) ? appointment.dup : appointment if appointment
      return lead.appointments.new if activity.metadata["external_key"].present?

      lead.appointments.find_or_initialize_by(
        admin_user: action[:admin_user],
        title: action[:title],
        starts_at: action[:due_at]
      )
    end

    def canonical_activities(lead)
      scope = lead.activities.where(kind: %w[external_scheduled_action external_appointment])
                  .where("metadata @> ?", { source: SOURCE }.to_json)
      scope.where(id: scope.select("MAX(id)").group("metadata ->> 'external_key'"))
    end

    def shared_record?(activity, lead, field, id)
      first_id = @first_activity_by_record[[lead.id, field, id.to_s]]
      first_id && first_id < activity.id
    end

    def prepare_identity_index
      lead_ids = scheduled_activities.except(:includes).select(:lead_id)
      rows = LeadActivity.where(lead_id: lead_ids, kind: %w[external_scheduled_action external_appointment])
        .where("metadata @> ?", { source: SOURCE }.to_json)
        .pluck(:id, :lead_id, Arel.sql("metadata ->> 'external_key'"), Arel.sql("metadata ->> 'task_id'"), Arel.sql("metadata ->> 'appointment_id'"))
      latest = rows.group_by { |row| [row[1], row[2]] }.values.map { |group| group.max_by(&:first) }
      @canonical_activity_ids = latest.to_h { |row| [row[0], true] }
      @first_activity_by_record = {}
      latest.sort_by(&:first).each do |id, lead_id, _, task_id, appointment_id|
        @first_activity_by_record[[lead_id, "task_id", task_id]] ||= id if task_id
        @first_activity_by_record[[lead_id, "appointment_id", appointment_id]] ||= id if appointment_id
      end
    end

    def legacy_task_for(activity, lead)
      task_id = activity.metadata["task_id"]
      return nil if task_id.blank?

      lead.tasks.find_by(id: task_id)
    end

    def cancel_legacy_task!(activity, lead)
      task = legacy_task_for(activity, lead)
      return if task.blank? || task.status == "cancelada"
      return if canonical_activities(lead).where(kind: "external_scheduled_action").where.not(id: activity.id)
        .where("metadata ->> 'task_id' = ?", task.id.to_s).exists?

      task.update!(status: "cancelada") if execute
      result.tasks_cancelled += 1
    end

    def update_activity!(activity, **attributes)
      metadata = activity.metadata.merge(attributes.stringify_keys).merge("unassigned" => false).except("unassigned_reason")
      kind = attributes[:appointment_id] ? "external_appointment" : activity.kind
      activity.update!(metadata: metadata, kind: kind) if metadata != activity.metadata || kind != activity.kind
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
          activity.metadata["due_at"].presence || activity.metadata["starts_at"]
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
      lead&.admin_user || mapped_seller_user(raw)
    end

    def operational_lead?(lead)
      return false if lead.blank?
      return false unless lead.admin_user&.active?
      return false if Lead.non_operational_status_values(tenant: lead.tenant).include?(lead.status)
      return false if lead.lead_pipeline_stage&.stage_type.in?(%w[won lost archived])

      true
    end

    def mapped_seller_user(raw)
      return if integration.blank?

      seller = {
        "id" => raw["seller_id"].presence || raw.dig("seller", "id"),
        "email" => raw["seller_email"].presence || raw.dig("seller", "email"),
        "phone" => raw["seller_phone"].presence || raw.dig("seller", "phone"),
        "name" => raw["seller_name"].presence || raw.dig("seller", "name")
      }.compact

      integration.local_user_for_seller(seller)
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
      return "concluida" if status.include?("finalizado") || status.include?("concluido") || status.match?(/\Arealizad[oa](?:_|$)/) || status == "true"
      return "cancelada" if status.include?("cancel") || status.include?("fechada_automaticamente") || status.include?("reagendad")

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

    def skip_non_operational!
      result.skipped_non_operational += 1
    end
  end
end
