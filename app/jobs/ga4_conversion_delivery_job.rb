class Ga4ConversionDeliveryJob < ApplicationJob
  queue_as :default

  def perform(tenant_id, event_id)
    event = Ga4ConversionEvent.find_by(tenant_id: tenant_id, id: event_id)
    return unless event

    config = Ga4ConversionConfig.find_by(tenant_id: tenant_id)
    event.with_lock do
      return unless event.status == "pending"

      reason = skip_reason(event, config)
      event.update!(status: reason ? "skipped" : "sending", skip_reason: reason, attempted_at: Time.current)
      return if reason
    end

    result = Ga4::MeasurementClient.deliver(config: config, payload: event.measurement_payload)
    event.update!(status: result.outcome, http_status: result.http_status)
    Rails.logger.info("[GA4_CRM] event_id=#{event.event_id} event=#{event.event_name} status=#{event.status} http_status=#{event.http_status}")
  end

  private

  def skip_reason(event, config)
    return "tenant_mismatch" unless event.lead.tenant_id == event.tenant_id
    return "config_inactive" unless config&.active?
    return "destination_changed" unless config.measurement_id == event.measurement_id
    return "before_activation" if event.occurred_at < config.activated_at
    return "expired" if event.occurred_at < 72.hours.ago
    return "future_event" if event.occurred_at > Time.current

    attribution = event.lead.attribution_data.to_h
    return "consent_missing" unless attribution["analytics_consent"] == "granted"
    return "identity_changed" unless attribution["client_id"] == event.client_id

    nil
  end
end
