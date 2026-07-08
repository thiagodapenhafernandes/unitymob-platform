class SystemNotificationSetting < ApplicationRecord
  include EncryptionAvailability

  # Singleton GLOBAL (sem tenant_id): transporte de notificação do Admin do
  # Sistema. Usado como fallback opt-in por conta (Tenant#use_global_*_fallback?)
  # quando o tenant não tem integração/SMTP próprios. Credenciais criptografadas
  # via AR Encryption (chaves por ENV, mesmo esquema do EmailSetting/PushSetting).
  encrypts :whatsapp_access_token
  encrypts :facebook_app_secret
  encrypts :whatsapp_app_secret

  # Singleton.
  def self.instance
    first_or_create!
  end

  # Pronto para enviar WhatsApp pela conta global (gate do fallback global).
  def whatsapp_configured?
    return false unless encryption_ready?

    whatsapp_enabled? &&
      whatsapp_access_token.present? &&
      whatsapp_phone_number_id.present?
  rescue ActiveRecord::Encryption::Errors::Base
    false
  end

  # Secret do App Meta (nível de app) usado na validação do webhook de leads.
  # Campo explícito vence; senão cai no ENV (compat com deploys atuais).
  def meta_app_secret
    stored = read_encrypted_secret(:facebook_app_secret)
    stored.presence || ENV["FACEBOOK_APP_SECRET"].presence
  end

  # Secret do produto WhatsApp: campo próprio > ENV WHATSAPP_APP_SECRET > secret
  # do App Meta (meta_app_secret). Os webhooks da Cloud API são assinados com o
  # App Secret do Facebook, então sem esse encadeamento o fail-closed rejeitaria
  # todo webhook real quando só FACEBOOK_APP_SECRET está configurado.
  def wa_app_secret
    stored = read_encrypted_secret(:whatsapp_app_secret)
    stored.presence || ENV["WHATSAPP_APP_SECRET"].presence || meta_app_secret
  end

  # Ativado (guard pré-migration para whatsapp_enabled).
  def whatsapp_enabled?
    return false unless has_attribute?(:whatsapp_enabled)

    self[:whatsapp_enabled] == true
  end

  private

  # Leitura defensiva de campo criptografado: sem chaves de criptografia (ou
  # payload legado) não estoura — retorna nil e deixa o ENV assumir.
  def read_encrypted_secret(attribute)
    return nil unless has_attribute?(attribute)
    return nil unless encryption_ready?

    public_send(attribute)
  rescue ActiveRecord::Encryption::Errors::Base
    nil
  end
end
