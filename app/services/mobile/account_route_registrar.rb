# frozen_string_literal: true

require "faraday"

module Mobile
  # Mantém o gateway central de discovery (app híbrido) sincronizado
  # automaticamente com os AdminUsers desta conta — sem cadastro manual por
  # usuário. Cada servidor físico (um por cliente) roda essa sincronização
  # apontando pro seu próprio GATEWAY_URL/PUBLIC_APP_URL.
  #
  # GATEWAY_URL/GATEWAY_INTERNAL_TOKEN caem por padrão nas mesmas variáveis já
  # usadas pelo webhook do WhatsApp (WHATSAPP_WEBHOOK_GATEWAY_*) — é o MESMO
  # serviço gateway/ e o MESMO INTERNAL_API_TOKEN, então todo cliente que já
  # tem o webhook configurado não precisa duplicar nada. Só falta mesmo a
  # variável nova, específica deste servidor:
  #
  # ENV esperadas (ausentes = no-op, não quebra o app):
  #   PUBLIC_APP_URL         — URL pública deste servidor (ex.: https://app.conexaobc.com)
  #   GATEWAY_URL            — (opcional) sobrepõe WHATSAPP_WEBHOOK_GATEWAY_URL
  #   GATEWAY_INTERNAL_TOKEN — (opcional) sobrepõe WHATSAPP_WEBHOOK_GATEWAY_INTERNAL_TOKEN
  class AccountRouteRegistrar
    def self.sync!(admin_user)
      new.sync!(admin_user)
    end

    def self.deactivate!(email)
      new.deactivate!(email)
    end

    def sync!(admin_user)
      return unless configured?
      return if admin_user.email.blank?

      response = connection.post("/internal/account_routes") do |req|
        req.headers["Authorization"] = "Bearer #{token}"
        req.headers["Content-Type"] = "application/json"
        req.body = {
          email: admin_user.email,
          tenant_name: admin_user.tenant&.name,
          target_url: public_app_url
        }.to_json
      end

      log_failure("sync", admin_user.email, response) unless response.success?
    rescue Faraday::Error => e
      Rails.logger.warn("[Mobile::AccountRouteRegistrar] falha ao sincronizar email=#{admin_user.email}: #{e.class}: #{e.message}")
    end

    def deactivate!(email)
      return unless configured?
      return if email.blank?

      response = connection.delete("/internal/account_routes/#{ERB::Util.url_encode(email)}") do |req|
        req.headers["Authorization"] = "Bearer #{token}"
      end

      log_failure("deactivate", email, response) unless response.success? || response.status == 404
    rescue Faraday::Error => e
      Rails.logger.warn("[Mobile::AccountRouteRegistrar] falha ao desativar email=#{email}: #{e.class}: #{e.message}")
    end

    def configured?
      gateway_url.present? && token.present? && public_app_url.present?
    end

    private

    def gateway_url
      ENV["GATEWAY_URL"].presence || ENV["WHATSAPP_WEBHOOK_GATEWAY_URL"]
    end

    def token
      ENV["GATEWAY_INTERNAL_TOKEN"].presence || ENV["WHATSAPP_WEBHOOK_GATEWAY_INTERNAL_TOKEN"]
    end

    def public_app_url
      ENV["PUBLIC_APP_URL"]
    end

    def connection
      @connection ||= Faraday.new(url: gateway_url)
    end

    def log_failure(action, email, response)
      Rails.logger.warn(
        "[Mobile::AccountRouteRegistrar] #{action} falhou email=#{email} status=#{response.status} body=#{response.body}"
      )
    end
  end
end
