module Admin::ImovelwebHelper
  def imovelweb_production_badge(connections)
    connection = connections.find(&:receiving?) || connections.find { |item| item.authorized_at.present? }
    label = connection ? imovelweb_connection_status(connection) : "Autorização do portal pendente"
    ax_badge(label, tone: connection&.receiving? ? :green : :amber)
  end

  def imovelweb_connection_status(connection)
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
