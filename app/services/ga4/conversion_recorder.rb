module Ga4
  # Registra dentro da transação de domínio; a rede só é acionada após commit.
  class ConversionRecorder
    QUALIFICATION_FIELDS = %w[broker_qualification_status manager_qualification_status].freeze

    def self.lead_updated(lead)
      qualified = QUALIFICATION_FIELDS.any? do |field|
        lead.saved_change_to_attribute?(field) && lead.public_send(field) == "qualified"
      end
      previously_qualified = QUALIFICATION_FIELDS.any? do |field|
        (lead.saved_change_to_attribute?(field) ? lead.saved_change_to_attribute(field).first : lead.public_send(field)) == "qualified"
      end
      if qualified && !previously_qualified
        record(lead: lead, event_name: "qualify_lead", key: "lead:#{lead.id}:qualified")
      end
      if (lead.saved_change_to_status? || lead.saved_change_to_lead_pipeline_stage_id?) && lead.lead_pipeline_stage&.stage_type == "won"
        record(lead: lead, event_name: "close_convert_lead", key: "lead:#{lead.id}:won")
      end
    end

    def self.appointment_updated(appointment)
      return unless appointment.saved_change_to_status? && appointment.realizado? && appointment.kind == "visita"
      return unless appointment.lead && appointment.tenant_id == appointment.lead.tenant_id

      record(lead: appointment.lead, event_name: "visit_completed", key: "appointment:#{appointment.id}:completed", property: appointment.habitation)
    end

    def self.proposal_updated(proposal)
      return unless proposal.saved_change_to_status? && proposal.status == "enviada"

      record(lead: proposal.lead, event_name: "proposal_sent", key: "proposal:#{proposal.id}:sent", property: proposal.habitation)
    end

    def self.record(lead:, event_name:, key:, property: nil)
      attribution = lead.attribution_data.to_h
      return unless attribution["analytics_consent"] == "granted" && attribution["client_id"].to_s.match?(/\A\d{1,20}\.\d{1,20}\z/)

      Ga4ConversionEvent.transaction(requires_new: true) do
        config = Ga4ConversionConfig.find_by(tenant_id: lead.tenant_id)
        next unless config&.active?

        property ||= lead.tenant.habitations.find_by(id: lead.property_id) if lead.property_id.present?
        next if property && property.tenant_id != lead.tenant_id

        business_type = Leads::Attribution.business_type(attribution["business_type"])
        business_type = "geral" unless Leads::Attribution::BUSINESS_TYPE_VALUES.values.include?(business_type)
        Ga4ConversionEvent.create_or_find_by!(tenant_id: lead.tenant_id, deduplication_key: key) do |event|
          event.lead = lead
          event.event_name = event_name
          event.event_id = SecureRandom.uuid
          event.measurement_id = config.measurement_id
          event.client_id = attribution["client_id"]
          event.occurred_at = Time.current
          event.parameters = {
            "business_type" => business_type, "property_code" => property&.codigo.to_s.first(100),
            "event_id" => event.event_id, "lead_source" => "crm"
          }
        end
      end
    rescue ActiveRecord::ActiveRecordError => error
      Rails.logger.warn("[GA4_CRM] capture_failed tenant_id=#{lead.tenant_id} event=#{event_name} error_class=#{error.class.name}")
      nil
    end
  end
end
