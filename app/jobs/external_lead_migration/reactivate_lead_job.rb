module ExternalLeadMigration
  class ReactivateLeadJob < ApplicationJob
    queue_as :sync

    class InvalidContext < StandardError; end
    class InvalidResponse < StandardError; end

    def perform(reactivation_id, tenant_id:)
      tenant = Tenant.find_by(id: tenant_id)
      operation = tenant&.c2s_lead_reactivations&.find_by(id: reactivation_id)
      return unless operation

      acquired = LeadLock.synchronize(operation.lead_id) { process!(operation.reload) }
      unless acquired
        if executions < 12
          retry_job wait: 5.seconds
        else
          fail_operation!(operation, InvalidContext.new("C2S ocupado: reativação não iniciada"))
        end
      end
    rescue StandardError => error
      raise unless operation
      fail_operation!(operation, error)
    end

    private

    def process!(operation)
      return if %w[completed failed uncertain].include?(operation.status)
      if %w[reactivating redistributing].include?(operation.status)
        fail_operation!(operation, InvalidResponse.new("Operação anterior sem confirmação"))
        return
      end

      validate_context!(operation)
      client = Client.new(token: operation.external_lead_integration.access_token)
      external_id = operation.external_lead_id
      remote = client.lead(external_id)
      raise InvalidResponse, "Cadastro C2S não confirmado" unless remote_id(remote) == external_id

      if operation.reactivated_at && remote_attributes(remote).dig("lead_status", "id").to_s != "0"
        raise InvalidContext, "O cadastro C2S mudou após a reabertura; redistribuição não executada"
      end

      routing = operation.distribution_rule.c2s_routing_attributes(campaign: true)
      source = routing.fetch("source")
      client.update_lead_routing(external_id, attributes: routing)
      confirmed = client.lead(external_id)
      unless remote_id(confirmed) == external_id && remote_attributes(confirmed).dig("lead_source", "name").to_s.casecmp?(source)
        raise InvalidResponse, "Origem da campanha WhatsApp não confirmada no C2S; redistribuição não executada"
      end

      unless operation.reactivated_at
        operation.update!(status: "reactivating", error_message: nil)
        response = client.reactivate_lead(external_id,
          message: "Interesse confirmado na campanha Unitymob ##{operation.whatsapp_campaign_message.whatsapp_campaign_id}; referência #{operation.id}.")
        attributes = remote_attributes(response)
        unless remote_id(response) == external_id && attributes.dig("lead_status", "id").to_s == "0" && attributes.dig("archive_details", "archived") != true
          raise InvalidResponse, "Reabertura C2S não confirmada"
        end
        operation.update!(status: "reactivated", reactivated_at: Time.current)
      end

      validate_context!(operation)
      operation.update!(status: "redistributing")
      response = client.redistribute_lead(external_id)
      unless response.is_a?(Hash) && response["success"] == true && response["seller_id"].present?
        raise InvalidResponse, "Redistribuição C2S não confirmada"
      end
      operation.update!(status: "completed", redistributed_at: Time.current, seller_id: response["seller_id"], error_message: nil)
      LeadActivity.log!(lead: operation.lead, kind: "c2s_reactivation_completed", metadata: {
        reactivation_id: operation.id, whatsapp_campaign_message_id: operation.whatsapp_campaign_message_id,
        external_lead_id: external_id, seller_id: operation.seller_id, rule_id: operation.distribution_rule_id
      })
    end

    def validate_context!(operation)
      operation.distribution_rule&.reload
      operation.external_lead_integration&.reload
      message = operation.whatsapp_campaign_message
      rule = operation.distribution_rule
      integration = operation.external_lead_integration
      unless message&.replied? && message.tenant_id == operation.tenant_id &&
          (message.lead_id == operation.lead_id || message.whatsapp_campaign_recipient&.lead_id == operation.lead_id) &&
          rule&.tenant_id == operation.tenant_id && rule.active? && rule.source_whatsapp_campaign? && rule.destination_c2s? &&
          C2sLeadReactivation.positive_reply_for?(message, rule)
        raise InvalidContext, "Resposta ou fila C2S indisponível para esta conta"
      end
      unless integration&.connected? && integration.tenant_id == operation.tenant_id &&
          operation.lead.c2s_existing_id_for(integration) == operation.external_lead_id
        raise InvalidContext, "Integração ou vínculo com o lead C2S indisponível"
      end
    end

    def remote_attributes(response)
      data = response.is_a?(Hash) && response["data"].is_a?(Hash) ? response["data"] : response
      return {} unless data.is_a?(Hash)
      data["attributes"].is_a?(Hash) ? data["attributes"] : data
    end

    def remote_id(response)
      return unless response.is_a?(Hash)
      data = response["data"].is_a?(Hash) ? response["data"] : response
      data["id"].to_s.presence
    end

    def fail_operation!(operation, error)
      operation.reload
      return if operation.status == "completed"
      uncertain = %w[reactivating redistributing uncertain].include?(operation.status)
      detail = if error.is_a?(InvalidContext) || error.is_a?(InvalidResponse)
        error.message
      else
        [error.class.name, ("HTTP #{error.http_status}" if error.respond_to?(:http_status) && error.http_status)].compact.join(" · ")
      end
      message = uncertain ? "C2S sem confirmação; conferir antes de reenviar: #{detail}" : "Reativação não executada: #{detail}"
      operation.update!(status: uncertain ? "uncertain" : "failed", error_message: message)
      LeadActivity.log!(lead: operation.lead, kind: uncertain ? "c2s_reactivation_uncertain" : "c2s_reactivation_failed",
        metadata: { reactivation_id: operation.id, error_class: error.class.name, rule_id: operation.distribution_rule_id, reason: message })
    end
  end
end
