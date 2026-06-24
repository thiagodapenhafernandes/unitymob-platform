module Webhooks
  class InboundController < ApplicationController
    skip_before_action :verify_authenticity_token
    skip_before_action :load_layout_settings

    before_action :authenticate_token!

    def leads
      result = InboundWebhooks::LeadReceiver.call(
        token: @inbound_webhook_token,
        payload: inbound_payload,
        request:
      )

      if result.success?
        render json: {
          ok: true,
          lead_id: result.lead.id,
          status: result.lead.status,
          distribution_rule_id: result.lead.distribution_rule_id
        }, status: :created
      else
        render json: { error: "Payload inválido", details: result.errors }, status: :unprocessable_entity
      end
    end

    private

    def authenticate_token!
      @inbound_webhook_token = InboundWebhookToken.authenticate(inbound_token_value)
      return if @inbound_webhook_token

      render json: { error: "Token inválido" }, status: :unauthorized
    end

    def inbound_token_value
      authorization_bearer_token.presence ||
        request.headers["X-Webhook-Token"].presence ||
        request.headers["X-Inbound-Webhook-Token"].presence ||
        params[:token].presence
    end

    def authorization_bearer_token
      authorization = request.headers["Authorization"].to_s
      match = authorization.match(/\ABearer\s+(.+)\z/i)
      match && match[1].to_s.strip
    end

    def inbound_payload
      request.request_parameters.presence || parsed_body
    end

    def parsed_body
      JSON.parse(request.raw_post)
    rescue JSON::ParserError
      {}
    end
  end
end
