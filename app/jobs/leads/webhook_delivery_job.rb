module Leads
  # Entrega assíncrona do lead distribuído para uma URL de webhook externo.
  # Uma URL por job para isolar falhas/retries entre destinos. O POST (com retry
  # e backoff) fica em WebhookService.
  class WebhookDeliveryJob < ApplicationJob
    queue_as :default

    def perform(url, payload)
      return if url.blank?
      data = payload.to_h.deep_stringify_keys
      lead_data = data["lead"].to_h
      if lead_data["id"].present?
        lead = Lead.where(tenant_id: lead_data["tenant_id"]).find_by(id: lead_data["id"])
        return unless lead&.notifications_allowed?
      end
      corretor_id = payload.to_h.dig("corretor", "id") || payload.to_h.dig(:corretor, :id)
      if corretor_id.present?
        corretor = AdminUser.find_by(id: corretor_id)
        return unless corretor&.active? && corretor.notification_delivery_allowed?
      end

      WebhookService.send_form_data("lead_distributed", payload, url: url)
    end
  end
end
