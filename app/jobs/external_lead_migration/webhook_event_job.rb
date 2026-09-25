module ExternalLeadMigration
  class WebhookEventJob < ApplicationJob
    queue_as :sync

    retry_on StandardError, wait: :polynomially_longer, attempts: 5

    # RecordInvalid é determinístico (validação nunca passa em retentativa):
    # descarta sem retry para não multiplicar o erro nem prender a fila sync.
    # Definido após o retry_on de propósito — o último handler vence.
    discard_on ActiveRecord::RecordInvalid

    def perform(integration_id, payload)
      integration = ExternalLeadIntegration.find(integration_id)
      return unless integration.connected?

      payload = payload.to_h.deep_stringify_keys
      payload = enrich_payload_if_needed(integration, payload)
      result = ExternalLeadMigration::LeadUpsert.call(integration:, payload:, historical: false)

      integration.update!(
        last_webhook_at: Time.current,
        last_cursor_at: Time.current,
        sync_status: "completed",
        sync_message: "Webhook externo processado para lead ##{result.lead&.id}."
      )
    end

    private

    def enrich_payload_if_needed(integration, payload)
      mapper = ExternalLeadMigration::LeadMapper.new(payload)
      return payload if mapper.external_lead_id.blank? || payload.dig("data", "attributes").present? || payload.dig("lead", "attributes").present?

      ExternalLeadMigration::Client.new(token: integration.access_token).lead(mapper.external_lead_id)
    end
  end
end
