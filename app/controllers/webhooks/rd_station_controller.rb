module Webhooks
  class RdStationController < ApplicationController
    skip_before_action :verify_authenticity_token
    skip_before_action :load_layout_settings

    before_action :load_tenant!

    def receive
      result = RdStation::LeadReceiver.call(
        tenant: @tenant,
        payload: inbound_payload,
        request:
      )

      if result.success?
        render json: { ok: true, lead_id: result.lead.id }, status: :created
      else
        render json: { error: "Payload inválido", details: result.errors }, status: :unprocessable_entity
      end
    end

    private

    def load_tenant!
      @tenant = RdStationIntegrationSetting.find_tenant_by_webhook_secret(params[:token])
      return if @tenant

      render json: { error: "Token inválido" }, status: :unauthorized
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
