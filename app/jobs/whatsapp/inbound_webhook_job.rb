module Whatsapp
  # Processa o payload do webhook da Cloud API fora do ciclo do request do Puma
  # (download de mídia, queries de campanha, criação de lead e automações rodam
  # no worker). O controller só valida, enfileira e responde 200 à Meta.
  # Retry é seguro: o InboundProcessor deduplica por wa_message_id e a
  # progressão de status é monotônica; falha definitiva cai em FailedExecution
  # do SolidQueue (visível/retentável), nunca some silenciosamente.
  class InboundWebhookJob < ApplicationJob
    queue_as :realtime
    self.log_arguments = false

    retry_on ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout,
             wait: :polynomially_longer, attempts: 5
    retry_on ActiveRecord::ConnectionNotEstablished, ActiveRecord::ConnectionTimeoutError,
             wait: :polynomially_longer, attempts: 5

    def perform(payload)
      # Tenant é resolvido pelo próprio processor a partir do payload
      # (Current.tenant setado/limpo internamente por change).
      Whatsapp::InboundProcessor.call(payload)
    end
  end
end
