class PortalLeadGatewaySyncJob < ApplicationJob
  queue_as :sync
  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  def perform(integration_id)
    integration = PortalIntegration.find_by(id: integration_id)
    return unless integration&.grupozap_family?

    # ponytail: HTTP sob lock por integração; separar envio e revisão se houver contenção.
    integration.with_lock do
      integration.update!(lead_route_key: SecureRandom.uuid) if integration.lead_route_key.blank?
      Portal::LeadGatewayClient.sync!(integration)
      integration.update!(lead_gateway_synced_at: Time.current, lead_gateway_error: nil)
    end
    publish_status(integration)
  rescue StandardError => error
    message = if error.message == "Autenticação do Grupo OLX pendente no Gateway."
      "Aguardando a chave de homologação do Grupo OLX. A URL já está cadastrada no Gateway."
    else
      "Não foi possível atualizar a conexão. Tentaremos novamente automaticamente."
    end
    integration&.update_columns(lead_gateway_error: message)
    publish_status(integration) if integration
    raise error
  end

  private

  def publish_status(integration)
    Turbo::StreamsChannel.broadcast_replace_to(integration, :lead_connection,
      target: "portal_lead_connection_#{integration.id}",
      partial: "admin/portal_integrations/lead_connection", locals: { integration: integration })
  end
end
