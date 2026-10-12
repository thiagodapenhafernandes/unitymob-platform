module Leads
  class OutboundWebhook
    def self.dispatch_changes(lead)
      events = {}
      if lead.saved_change_to_status? || lead.saved_change_to_lead_pipeline_stage_id?
        events["lead_stage_changed"] = {
          status: lead.saved_change_to_status,
          lead_pipeline_stage_id: lead.saved_change_to_lead_pipeline_stage_id
        }.compact
      end
      qualification = %w[broker_qualification_status manager_qualification_status].filter_map do |field|
        [field, lead.saved_change_to_attribute(field)] if lead.saved_change_to_attribute?(field)
      end.to_h
      if qualification.any?
        events["lead_qualification_changed"] = qualification
        events["qualified_lead"] = qualification if qualification.values.any? { |change| change.last == "qualified" }
      end
      return if events.empty?

      settings = lead.tenant.webhook_settings.active
      return unless settings.any? { |setting| events.keys.any? { |event| setting.delivers_event?(event) } }

      property = lead.tenant.habitations.find_by(id: lead.property_id) if lead.property_id.present?
      events.each do |event, changes|
        WebhookService.send_form_data(event, lead.attributes.merge(
          "property_code" => property&.codigo,
          "changes" => changes.transform_values { |from, to| { from: from, to: to } }
        ), tenant: lead.tenant)
      end
    end
  end
end
