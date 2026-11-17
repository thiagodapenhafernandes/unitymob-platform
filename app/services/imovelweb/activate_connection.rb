module Imovelweb
  class ActivateConnection
    def self.call(connection)
      connection.with_lock do
        if connection.receiving? && connection.gateway_synced_at.present?
          connection.update!(connection_error: nil) if connection.connection_error.present?
          next true
        end
        unless connection.authorization_requested_at.present? || connection.authorized_at.present?
          raise GatewayClient::Error, "Inicie a autorização no Imovelweb antes de verificar."
        end
        # Old numeric codes are not proof that the current tenant owns that advertiser.
        unless connection.authorized_at.present? || connection.client_code.match?(/\A(?:pending|um)-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
          raise GatewayClient::Error, "Esta conexão precisa de uma nova autorização no Imovelweb."
        end
        advertiser = GatewayClient.verify!(connection)
        unless advertiser
          connection.update!(connection_error: nil)
          next false
        end
        if connection.advertiser_code.present? && connection.advertiser_code != advertiser
          raise GatewayClient::Error, "A sucursal autorizada é diferente da conta informada. Autorize a sucursal correta no Imovelweb."
        end
        unless connection.encryption_ready? && ENV["IMOVELWEB_RECEIVING_ENABLED"] == "true" && connection.tenant.active?
          raise GatewayClient::Error, "O recebimento do Imovelweb está indisponível neste ambiente."
        end
        connection.update!(advertiser_code: advertiser, authorized_at: connection.authorized_at || Time.current, enabled: true)
        GatewayClient.sync!(connection)
        connection.update!(gateway_synced_at: Time.current, connection_error: nil)
        true
      end
    end
  end
end
