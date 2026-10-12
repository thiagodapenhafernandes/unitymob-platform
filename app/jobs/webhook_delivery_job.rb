# Entrega assíncrona dos webhooks de formulários/leads montados pelo
# WebhookService (payload/assinatura permanecem lá — contrato externo).
# Uma URL por job para isolar falhas entre destinos; retry com backoff via
# ActiveJob e, esgotadas as tentativas, a falha vira FailedExecution
# consultável no SolidQueue/Mission Control.
class WebhookDeliveryJob < ApplicationJob
  queue_as :default

  class DeliveryError < StandardError; end

  retry_on DeliveryError, wait: :polynomially_longer, attempts: 5

  def perform(url, payload)
    return if url.blank?

    result = WebhookService.deliver(url, payload)
    fields = payload.to_h.with_indifferent_access
    destination_host = URI.parse(url).host rescue nil
    delivery = {
      status: result[:success] ? "delivered" : "failed",
      event_name: fields[:event_name], event_id: fields[:event_id],
      transaction_id: fields[:transaction_id], origin_form: fields[:origin_form],
      destination_host: destination_host, http_status: result[:status], attempt: executions
    }
    Rails.logger.public_send(result[:success] ? :info : :error, "[WEBHOOK_DELIVERY] #{delivery.to_json}")
    return if result[:success]

    raise DeliveryError, "Webhook falhou (event_id=#{fields[:event_id]}, status=#{result[:status] || '-'})"

  end
end
