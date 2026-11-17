module Admin::ImovelwebHelper
  def imovelweb_production_badge(connections)
    connection = connections.find(&:receiving?) || connections.find { |item| item.authorized_at.present? }
    label = connection ? imovelweb_connection_status(connection) : "Autorização do portal pendente"
    ax_badge(label, tone: connection ? imovelweb_connection_tone(connection) : :amber)
  end

  def imovelweb_connection_tone(connection)
    ready = connection.receiving? && connection.connection_error.blank? && connection.listing_sync_error.blank? &&
      (connection.authorization_requested_at.blank? || connection.listings_synced_at.present?)
    ready ? :green : :amber
  end

  def imovelweb_connection_status(connection)
    return "Preparação dos anúncios pendente" if connection.listing_sync_error.present?
    return "Conexão pendente de atualização" if connection.connection_error.present?
    if connection.authorization_requested_at.present? && connection.enabled? && connection.gateway_synced_at.blank?
      return "Preparando recebimento"
    end
    if connection.authorization_requested_at.present? && connection.receiving? && connection.listings_synced_at.blank?
      return "Preparando contatos dos anúncios"
    end
    return "Recebimento ativo em #{connection.environment == 'production' ? 'produção' : 'sandbox'}" if connection.receiving?
    connection.authorized_at.present? ? "Recebimento pausado" : "Autorização do portal pendente"
  end

  def imovelweb_receipt_status(receipt)
    { "pending" => "Pendente", "processed" => "Processado", "quarantined" => "Em quarentena" }.fetch(receipt.status)
  end

  def imovelweb_receipt_reason(receipt)
    { "unknown_listing" => "Imóvel sem vínculo nesta conexão; evento retido sem criar lead.",
      "conflicting_listing" => "Referência e ID do anúncio apontam para imóveis diferentes.",
      "missing_contact" => "Contato sem telefone ou e-mail válido.",
      "invalid_payload" => "Dados do evento inválidos para esta conexão.",
      "invalid_lead" => "Não foi possível validar os dados do lead." }.fetch(receipt.reason, receipt.reason.presence || "Sem impedimento registrado")
  end
end
