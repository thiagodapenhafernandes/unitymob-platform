module Webhooks
  class ExternalLeadsController < ActionController::Base
    skip_forgery_protection

    def receive
      integration = ExternalLeadIntegration.find_by(webhook_token: params[:token].to_s, enabled: true, status: "connected", webhook_listening_enabled: true)
      return render json: { error: "Token inválido" }, status: :unauthorized unless integration

      integration.update_columns(last_webhook_at: Time.current, updated_at: Time.current)
      ExternalLeadMigration::WebhookEventJob.perform_later(integration.id, webhook_payload)
      render json: { ok: true }, status: :accepted
    end

    private

    def webhook_payload
      request.request_parameters.presence || JSON.parse(request.raw_post)
    rescue JSON::ParserError
      {}
    end
  end
end
