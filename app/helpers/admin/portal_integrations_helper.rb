module Admin::PortalIntegrationsHelper
  def portal_lead_connection_badge(integration)
    label, tone = if !Portal::LeadGatewayClient.configured?
      ["Suporte necessário", :amber]
    elsif integration.lead_gateway_error.present?
      ["Atualização pendente", :amber]
    elsif !integration.leads_receiving?
      ["Recebimento pausado", :amber]
    elsif integration.lead_gateway_synced_at.blank?
      ["Preparando conexão", :amber]
    elsif integration.last_lead_at.present?
      ["Lead recebido", :green]
    else
      ["Sem recebimento confirmado", :gray]
    end
    ax_badge(label, tone: tone)
  end
end
