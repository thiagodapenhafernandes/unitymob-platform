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
    origin_form = payload.is_a?(Hash) ? (payload[:origin_form] || payload["origin_form"]) : nil

    if result[:success]
      Rails.logger.info(
        "[WEBHOOK_DELIVERY] status=delivered origin_form=#{origin_form} url=#{url} " \
        "http_status=#{result[:status]} attempt=#{executions}"
      )
      return
    end

    Rails.logger.error(
      "[WEBHOOK_DELIVERY] status=failed origin_form=#{origin_form} url=#{url} " \
      "http_status=#{result[:status] || '-'} attempt=#{executions} error=#{result[:error]}"
    )
    raise DeliveryError, "Webhook para #{url} falhou (origin=#{origin_form}, status=#{result[:status] || '-'}): #{result[:error]}"
  end
end
