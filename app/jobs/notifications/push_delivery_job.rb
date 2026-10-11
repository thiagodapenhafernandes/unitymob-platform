# frozen_string_literal: true

module Notifications
  # Envio de push fora da request: o deliver faz HTTPS síncrono por
  # subscription (WebPush/FCM). Idempotente — o dispatcher revalida
  # usuário, allowlist, configuração e subscriptions a cada execução.
  class PushDeliveryJob < ApplicationJob
    queue_as :default

    retry_on Net::OpenTimeout, Net::ReadTimeout, Timeout::Error,
      Errno::ECONNRESET, Errno::ECONNREFUSED, EOFError, IOError,
      wait: :polynomially_longer, attempts: 3

    def perform(admin_user_id:, title:, body:, url:, notification_context: "general")
      PushDispatcher.deliver(
        admin_user_id: admin_user_id,
        title: title,
        body: body,
        url: url,
        urgency: "high",
        ttl: 3600,
        metadata: { notification_context: notification_context }
      )
    end
  end
end
