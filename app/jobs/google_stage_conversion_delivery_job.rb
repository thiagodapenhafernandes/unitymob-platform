class GoogleStageConversionDeliveryJob < ApplicationJob
  queue_as :default
  RETRY_DELAYS = [1.minute, 5.minutes, 30.minutes].freeze

  def perform(tenant_id, event_id)
    event = GoogleStageConversionEvent.find_by(tenant_id: tenant_id, id: event_id)
    return unless event

    event.with_lock do
      return unless event.status == "pending" && (!event.next_attempt_at || event.next_attempt_at <= Time.current)
      setting = WebhookSetting.find_by(tenant_id: tenant_id, id: event.webhook_setting_id)
      reason = if event.lead.tenant_id != tenant_id
        "tenant_mismatch"
      elsif !setting&.enabled? || !setting.google_conversions_enabled?
        "destination_inactive"
      elsif setting.google_destination_url != event.destination_url
        "destination_changed"
      elsif Automation::WebhookUrlPolicy.blocked?(event.destination_url)
        "destination_blocked"
      end
      if reason
        event.update!(status: "skipped", skip_reason: reason)
        return
      end

      count = event.attempt_count + 1
      status = nil
      error_class = nil
      begin
        payload = event.payload_data
        payload["diagnostic"] = true unless Rails.env.production?
        headers = { "Content-Type" => "application/json", "User-Agent" => "Unitymob-Google-Conversions/1.0" }
        headers["X-Webhook-Secret"] = setting.webhook_secret if setting.webhook_secret.present?
        response = HTTParty.post(event.destination_url, body: JSON.generate(payload), headers: headers, timeout: WebhookService::TIMEOUT, follow_redirects: false)
        status = response.code.to_i
      rescue StandardError => error
        error_class = error.class.name
      end
      success = status&.between?(200, 299)
      delay = RETRY_DELAYS[count - 1] unless success
      event.update!(
        attempt_count: count,
        attempt_log: event.attempt_log + [{ "attempt" => count, "at" => Time.current.iso8601, "http_status" => status, "error_class" => error_class }.compact],
        status: success ? "delivered" : delay ? "pending" : "failed",
        next_attempt_at: delay ? Time.current + delay : nil
      )
      Rails.logger.info("[GOOGLE_STAGE] tenant_id=#{tenant_id} event_id=#{event.id} attempt=#{count} status=#{event.status} http_status=#{status}")
    end
    event.enqueue_delivery if event.reload.status == "pending"
  end
end
