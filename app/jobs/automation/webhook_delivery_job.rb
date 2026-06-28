module Automation
  class WebhookDeliveryJob < ApplicationJob
    queue_as :default

    retry_on Net::OpenTimeout,
             Net::ReadTimeout,
             Timeout::Error,
             Automation::WebhookDeliveryService::TransientError,
             wait: :polynomially_longer,
             attempts: 3

    def perform(delivery_id)
      delivery = AutomationWebhookDelivery.find_by(id: delivery_id)
      return unless delivery
      return if delivery.status == "success"

      Automation::WebhookDeliveryService.call(delivery)
    end
  end
end
