module Webhooks
  class WhatsappController < ApplicationController
    skip_before_action :verify_authenticity_token

    # GET — verificação do webhook (challenge da Meta)
    def verify
      integration = WhatsappBusinessIntegration.current
      expected = integration.webhook_verify_token.presence

      if params["hub.mode"] == "subscribe" && expected.present? &&
         ActiveSupport::SecurityUtils.secure_compare(params["hub.verify_token"].to_s, expected)
        render plain: params["hub.challenge"]
      else
        head :forbidden
      end
    end

    # POST — recebimento de mensagens e status
    def receive
      Whatsapp::InboundProcessor.call(params.to_unsafe_h)
      head :ok
    rescue => e
      Rails.logger.error("[wa webhook] #{e.class}: #{e.message}")
      head :ok # responde 200 sempre para a Meta não entrar em retry-storm
    end
  end
end
