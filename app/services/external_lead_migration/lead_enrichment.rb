module ExternalLeadMigration
  class LeadEnrichment
    SOURCE = LeadMapper::PROVIDER_KEY

    def self.call(lead:, integration:, mapper:, historical:)
      new(lead:, integration:, mapper:, historical:).call
    end

    def initialize(lead:, integration:, mapper:, historical:)
      @lead = lead
      @integration = integration
      @mapper = mapper
      @historical = historical
    end

    def call
      create_property_interest!
      sync_labels!
      log_first_message!
      log_messages!
      log_entries!
      sync_scheduled_actions!
    end

    private

    attr_reader :lead, :integration, :mapper, :historical

    def create_property_interest!
      return if lead.property_id.blank?

      lead.property_interests.find_or_create_by!(habitation_id: lead.property_id) do |interest|
        interest.tenant = lead.tenant
      end
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      nil
    end

    def sync_labels!
      return if responsible_user.blank?

      mapper.label_names.each do |name|
        label = responsible_user.lead_labels.find_or_initialize_by(name: name)
        label.tenant ||= lead.tenant
        label.color ||= "gray"
        label.save! if label.changed?

        lead.lead_labelings.find_or_create_by!(lead_label: label) do |labeling|
          labeling.tenant = lead.tenant
        end
      end
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      nil
    end

    def log_first_message!
      body = mapper.first_message.to_s.strip
      return if body.blank?

      log_once!(
        kind: "external_first_message",
        key: "first_message:#{mapper.external_lead_id}",
        metadata: {
          body: body,
          historical: historical
        }
      )
    end

    def log_messages!
      mapper.messages.each_with_index do |message, index|
        key = message["id"].presence || message["message_id"].presence || "message:#{mapper.external_lead_id}:#{index}"
        log_once!(
          kind: "external_message",
          key: key,
          metadata: {
            body: message["body"].presence || message["message"].presence || message["text"],
            direction: message["direction"].presence || message["type"],
            sent_at: message["created_at"].presence || message["sent_at"]
          }.compact
        )
      end
    end

    def log_entries!
      mapper.log_entries.each_with_index do |entry, index|
        key = entry["id"].presence || entry["key"].presence || "log:#{mapper.external_lead_id}:#{index}:#{entry["created_at"]}"
        log_once!(
          kind: "external_log",
          key: key,
          metadata: {
            title: entry["title"].presence || entry["name"].presence || entry["action"],
            body: entry["body"].presence || entry["description"].presence || entry["message"],
            happened_at: entry["created_at"].presence || entry["date"],
            raw: entry
          }.compact
        )
      end
    end

    def sync_scheduled_actions!
      return if responsible_user.blank?

      mapper.scheduled_actions.each_with_index do |action, index|
        due_at = action_due_at(action)
        next if due_at.blank?

        if appointment_action?(action)
          sync_appointment!(action, due_at)
        else
          sync_task!(action, due_at, index)
        end
      end
    end

    def sync_task!(action, due_at, index)
      title = action_title(action)
      status = task_status(action)
      task = existing_task_for(action, index) ||
        lead.tasks.find_or_initialize_by(
          admin_user: responsible_user,
          title: title,
          due_at: due_at
        )
      task.assign_attributes(
        tenant: lead.tenant,
        created_by: integration.connected_by_admin_user,
        kind: task_kind(action),
        source: "external_legacy",
        status: status,
        completed_at: status == "concluida" ? due_at : nil,
        priority: "normal",
        description: action_description(action)
      )
      task.save!

      log_once!(
        kind: "external_scheduled_action",
        key: action["id"].presence || "scheduled:#{mapper.external_lead_id}:#{index}",
        metadata: { task_id: task.id, title: task.title, due_at: due_at.iso8601, raw: action }.compact
      )
    end

    def sync_appointment!(action, starts_at)
      title = action_title(action)
      appointment = existing_appointment_for(action, starts_at) ||
        lead.appointments.find_or_initialize_by(
          admin_user: responsible_user,
          title: title,
          starts_at: starts_at
        )
      appointment.assign_attributes(
        tenant: lead.tenant,
        habitation_id: lead.property_id,
        kind: appointment_kind(action),
        status: appointment_status(action),
        notes: action_description(action)
      )
      appointment.save!

      log_once!(
        kind: "external_appointment",
        key: action["id"].presence || "appointment:#{mapper.external_lead_id}:#{starts_at.to_i}",
        metadata: { appointment_id: appointment.id, title: appointment.title, starts_at: starts_at.iso8601, raw: action }.compact
      )
    end

    def log_once!(kind:, key:, metadata:)
      lookup = { source: SOURCE, external_key: key.to_s }
      return if lead.activities.where(kind: kind).where("metadata @> ?", lookup.to_json).exists?

      LeadActivity.log!(
        lead: lead,
        kind: kind,
        metadata: lookup.merge(metadata || {})
      )
    end

    def responsible_user
      @responsible_user ||= lead.admin_user || integration.connected_by_admin_user
    end

    def action_title(action)
      action["title"].presence ||
        action["name"].presence ||
        action["schedulated_action_name"].presence ||
        action["alias"].presence ||
        action["schedulated_action_type_alias"].presence ||
        action["type"].presence ||
        "Ação agendada do legado"
    end

    def action_description(action)
      action["description"].presence || action["observation"].presence || action["note"].presence
    end

    def action_due_at(action)
      parse_time(
        action["schedulated_action_date"].presence ||
          action["due_at"].presence ||
          action["scheduled_at"].presence ||
          action["date"].presence ||
          action["datetime"].presence ||
          action["created_at"]
      )
    end

    def appointment_action?(action)
      text = action_classification_text(action)
      text.include?("visita") || text.include?("reuniao")
    end

    def task_kind(action)
      text = action_classification_text(action)
      return "ligacao" if text.include?("ligacao") || text.include?("call")
      return "visita" if text.include?("visita")
      return "email" if text.include?("email")

      "follow_up"
    end

    def appointment_kind(action)
      text = action_classification_text(action)
      return "reuniao" if text.include?("reuniao")
      return "ligacao" if text.include?("ligacao")

      "visita"
    end

    def action_classification_text(action)
      [
        action["title"],
        action["name"],
        action["schedulated_action_name"],
        action["alias"],
        action["schedulated_action_type_alias"],
        action["type"]
      ].compact.join(" ").parameterize(separator: "_")
    end

    def existing_task_for(action, index)
      task_id = existing_activity_for("external_scheduled_action", action, index)&.metadata&.dig("task_id")
      return nil if task_id.blank?

      lead.tasks.find_by(id: task_id)
    end

    def existing_appointment_for(action, starts_at)
      key = action["id"].presence || "appointment:#{mapper.external_lead_id}:#{starts_at.to_i}"
      appointment_id = lead.activities
                           .where(kind: "external_appointment")
                           .where("metadata @> ?", { source: SOURCE, external_key: key.to_s }.to_json)
                           .pick(Arel.sql("metadata ->> 'appointment_id'"))
      return nil if appointment_id.blank?

      lead.appointments.find_by(id: appointment_id)
    end

    def existing_activity_for(kind, action, index)
      key = action["id"].presence || "scheduled:#{mapper.external_lead_id}:#{index}"
      lead.activities
          .where(kind: kind)
          .where("metadata @> ?", { source: SOURCE, external_key: key.to_s }.to_json)
          .first
    end

    def task_status(action)
      status = [action["status"], action["status_name"], action["done"]].compact.join(" ").parameterize(separator: "_")
      return "concluida" if status.include?("finalizado") || status.include?("concluido") || status == "true"
      return "cancelada" if status.include?("cancel")

      "pendente"
    end

    def appointment_status(action)
      status = [action["status"], action["status_name"], action["done"]].compact.join(" ").parameterize(separator: "_")
      return "realizado" if status.include?("finalizado") || status.include?("concluido") || status == "true"
      return "cancelado" if status.include?("cancel")

      "agendado"
    end

    def parse_time(value)
      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
