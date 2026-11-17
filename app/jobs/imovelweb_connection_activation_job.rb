class ImovelwebConnectionActivationJob < ApplicationJob
  queue_as :sync
  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  def perform(connection_id)
    connection = ImovelwebConnection.find_by(id: connection_id)
    return unless connection&.environment == "production" && connection.authorization_requested_at.present?
    return if connection.authorization_requested_at < 15.minutes.ago

    connected = Imovelweb::ActivateConnection.call(connection)
    publish_status(connection)
    if connected
      ImovelwebListingSyncJob.perform_later(connection.id)
    elsif connection.consent_confirmed_at.blank?
      self.class.set(wait: 30.seconds).perform_later(connection.id)
    end
  rescue StandardError
    connection&.update_columns(connection_error: "Não foi possível concluir a conexão. Verifique a sucursal autorizada e tente novamente.")
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
