module Imovelweb
  class ActivateConnection
    def self.call(connection)
      connection.with_lock do
        unless connection.authorization_requested_at.present? || connection.authorized_at.present?
          raise GatewayClient::Error, "Inicie a autorização no Imovelweb antes de verificar."
        end
        if connection.binding_editable? && !connection.advertiser_code.to_s.match?(/\A[0-9]{1,32}\z/)
          raise GatewayClient::Error, "Informe o código numérico da sucursal do Imovelweb."
        end
        if connection.binding_editable? && connection.client_code != connection.advertiser_code
          if connection.imovelweb_lead_receipts.exists? || connection.imovelweb_listings.exists?
            raise GatewayClient::Error, "Esta conexão possui histórico e não pode trocar de identidade. Cadastre uma nova conexão."
          end
          connection.update!(client_code: connection.advertiser_code)
        end
        result = GatewayClient.verify!(connection)
        unless result["confirmed"] || result["ownership_required"]
          connection.update!(connection_error: nil)
          next false
        end
        advertiser = result.fetch("advertiser_code")
        if connection.advertiser_code.present? && connection.advertiser_code != advertiser
          raise GatewayClient::Error, "A sucursal autorizada é diferente da conta informada. Autorize a sucursal correta no Imovelweb."
        end
        if result["ownership_required"]
          connection.update!(consent_confirmed_at: Time.current, binding_email_hint: result["email_hint"], connection_error: nil)
          next false
        end
        if connection.receiving? && connection.gateway_synced_at.present?
          connection.update!(connection_error: nil) if connection.connection_error.present?
          next true
        end
        unless connection.encryption_ready? && ENV["IMOVELWEB_RECEIVING_ENABLED"] == "true" && connection.tenant.active?
          raise GatewayClient::Error, "O recebimento do Imovelweb está indisponível neste ambiente."
        end
        connection.update!(advertiser_code: advertiser, authorized_at: connection.authorized_at || Time.current, enabled: true)
        GatewayClient.sync!(connection)
        connection.update!(gateway_synced_at: Time.current, connection_error: nil, binding_challenge_token: nil, binding_proof: nil)
        true
      end
    end
  end
end
