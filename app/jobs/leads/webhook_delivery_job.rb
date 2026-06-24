module Leads
  # Entrega assíncrona do lead distribuído para uma URL de webhook externo.
  # Uma URL por job para isolar falhas/retries entre destinos. O POST (com retry
  # e backoff) fica em WebhookService.
  class WebhookDeliveryJob < ApplicationJob
    queue_as :default

    def perform(url, payload)
      return if url.blank?

      WebhookService.send_form_data("lead_distributed", payload, url: url)
    end
  end
end
