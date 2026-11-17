class ImovelwebListingSyncJob < ApplicationJob
  queue_as :sync
  retry_on Imovelweb::GatewayClient::Error, wait: :polynomially_longer, attempts: 5

  def perform(connection_id, page = 0)
    connection = ImovelwebConnection.find_by(id: connection_id)
    return unless connection&.environment == "production" && connection.receiving?
    following = Imovelweb::GatewayClient.associate_listings!(connection, page: page)
    if following
      self.class.perform_later(connection.id, following)
    else
      connection.update!(listings_synced_at: Time.current, listing_sync_error: nil)
      publish_status(connection)
    end
  rescue Imovelweb::GatewayClient::Error
    connection&.update_columns(listing_sync_error: "Não foi possível preparar todos os anúncios para receber contatos. Tentaremos novamente automaticamente.")
    publish_status(connection) if connection
    raise
  end

  private

  def publish_status(connection)
    Turbo::StreamsChannel.broadcast_replace_to(connection, :connection_status,
      target: "imovelweb_connection_status_#{connection.id}",
      partial: "admin/portal_integrations/imovelweb_status", locals: { connection: connection })
  end
end
