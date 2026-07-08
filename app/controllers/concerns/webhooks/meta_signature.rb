module Webhooks
  # Validação do X-Hub-Signature-256 dos webhooks da Meta: HMAC-SHA256 do corpo
  # cru assinado com o app secret de NÍVEL DE APP (o webhook é assinado pelo
  # App Meta, não pela integração do tenant). O GET de verificação
  # (hub.challenge) não é assinado e fica fora desta checagem.
  #
  # FAIL-CLOSED: o secret vem de SystemNotificationSetting (com fallback ENV
  # embutido nos métodos meta_app_secret / wa_app_secret). Em produção, sem
  # secret o payload é RECUSADO (retorna false → o controller responde 403).
  # Fora de produção mantém a tolerância (aceita e loga warn) pra não travar dev.
  module MetaSignature
    SIGNATURE_HEADER = "X-Hub-Signature-256".freeze

    private

    def valid_meta_signature?(raw_body)
      secret = meta_webhook_app_secret
      if secret.blank?
        if Rails.env.production?
          Rails.logger.error("[meta webhook] app secret ausente em producao; payload rejeitado (#{request.path})")
          return false
        end

        Rails.logger.warn("[meta webhook] app secret ausente; X-Hub-Signature-256 nao validada em #{Rails.env} (#{request.path})")
        return true
      end

      signature = request.headers[SIGNATURE_HEADER].to_s.delete_prefix("sha256=")
      return false if signature.blank?

      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, raw_body.to_s)
      ActiveSupport::SecurityUtils.secure_compare(signature, expected)
    end

    # Secret do App Meta: config do Admin do Sistema vence, senão ENV
    # (fallback embutido em SystemNotificationSetting#meta_app_secret).
    # Tolerante se a tabela/model ainda não existir (pré-migration): cai no ENV.
    def meta_webhook_app_secret
      SystemNotificationSetting.instance.meta_app_secret
    rescue StandardError
      ENV["FACEBOOK_APP_SECRET"].presence
    end
  end
end
