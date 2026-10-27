module Leads
  class StageConversionEvents
    QUALIFICATION_FIELDS = %w[broker_qualification_status manager_qualification_status].freeze

    def self.lead_actions(lead)
      actions = []
      actions << "stage_entered" if lead.saved_change_to_lead_pipeline_stage_id?
      qualified = QUALIFICATION_FIELDS.any? { |field| lead.saved_change_to_attribute?(field) && lead.public_send(field) == "qualified" }
      previously_qualified = QUALIFICATION_FIELDS.any? do |field|
        (lead.saved_change_to_attribute?(field) ? lead.saved_change_to_attribute(field).first : lead.public_send(field)) == "qualified"
      end
      actions << "qualified" if qualified && !previously_qualified
      actions << "deal_closed" if (lead.saved_change_to_status? || lead.saved_change_to_lead_pipeline_stage_id?) && stage_for(lead)&.stage_type == "won"
      actions
    end

    def self.stage_for(lead)
      lead.tenant.lead_pipeline_stages.active.find_by(id: lead.lead_pipeline_stage_id, lead_pipeline_id: lead.lead_pipeline_id)
    end

    def self.dispatch(lead, actions, provider:, occurred_at: Time.current)
      return if lead.skip_automatic_routing? || actions.empty?

      stage = stage_for(lead)
      return unless stage

      if provider == :google
        setting = lead.tenant.webhook_settings.find_by(enabled: true, google_conversions_enabled: true)
        return unless setting

        event = stage.google_event if actions.include?(stage.google_event_trigger)
        GoogleConversions::Recorder.record(lead, setting, event, occurred_at: occurred_at) if GoogleConversions::Recorder::EVENTS.key?(event)
      elsif provider == :meta && stage.meta_conversion_event.present? && actions.include?(stage.meta_event_trigger)
        Meta::ConversionDispatcher.call(lead: lead, event_name: stage.meta_conversion_event, occurred_at: occurred_at)
      end
    rescue StandardError => error
      Rails.logger.warn("[STAGE_CONVERSION] tenant_id=#{lead.tenant_id} provider=#{provider} error_class=#{error.class.name}")
    end

    def self.appointment_updated(appointment, provider:)
      return unless appointment.saved_change_to_status? && appointment.realizado? && appointment.kind == "visita"
      return unless appointment.lead && appointment.tenant_id == appointment.lead.tenant_id

      dispatch(appointment.lead, ["visit_completed"], provider: provider, occurred_at: appointment.updated_at)
    end

    def self.proposal_updated(proposal, provider:)
      return unless proposal.saved_change_to_status? && proposal.status == "enviada"

      dispatch(proposal.lead, ["proposal_sent"], provider: provider, occurred_at: proposal.updated_at)
    end
  end
end
