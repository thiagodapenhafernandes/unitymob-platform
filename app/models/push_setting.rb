class PushSetting < ApplicationRecord
  include EncryptionAvailability

  encrypts :vapid_private_key

  # Destino do clique na notificação de novo lead (dentro do prazo do pocket).
  LEAD_CLICK_ACTIONS = %w[system whatsapp].freeze

  validates :lead_click_action, inclusion: { in: LEAD_CLICK_ACTIONS }, allow_blank: true

  # Singleton.
  def self.instance
    first_or_create!
  end

  def lead_click_action_value
    lead_click_action.presence_in(LEAD_CLICK_ACTIONS) || "system"
  end

  def open_whatsapp_on_click?
    lead_click_action_value == "whatsapp"
  end

  # Chaves efetivas: usa as personalizadas (salvas aqui); se vazias, cai para as
  # do ambiente (ENV) — que é o padrão recomendado quando o servidor já tem VAPID.
  def effective_public_key
    custom_public_key.presence || ENV["VAPID_PUBLIC_KEY"]
  end

  def effective_private_key
    custom_private_key.presence || ENV["VAPID_PRIVATE_KEY"]
  end

  def effective_subject
    subject_email.presence || ENV["VAPID_SUBJECT_EMAIL"]
  end

  # Origem das chaves em uso: :custom (geradas aqui), :env (config do servidor) ou :none.
  def keys_source
    return :custom if custom_public_key.present?

    ENV["VAPID_PUBLIC_KEY"].present? ? :env : :none
  end

  def env_keys_available?
    ENV["VAPID_PUBLIC_KEY"].present? && ENV["VAPID_PRIVATE_KEY"].present?
  end

  def keys_present?
    effective_public_key.present? && effective_private_key.present?
  end

  # Pronto para enviar Web Push (gate usado na regra de distribuição).
  def configured?
    enabled? && keys_present? && effective_subject.present?
  end

  # Gera um novo par de chaves VAPID personalizado (substitui as assinaturas push
  # existentes, que precisarão ser refeitas pelos dispositivos). Requer criptografia.
  def generate_keys!
    key = WebPush.generate_key
    update!(vapid_public_key: key.public_key, vapid_private_key: key.private_key)
  end

  # Volta a usar as chaves do ambiente (ENV), descartando as personalizadas.
  def use_env_keys!
    update!(vapid_public_key: nil, vapid_private_key: nil)
  end

  # Credenciais usadas pelo PushDispatcher.
  def vapid_credentials
    { subject: effective_subject, public_key: effective_public_key, private_key: effective_private_key }
  end

  # Chave pública para o endpoint do field/PWA (não sensível).
  def self.public_key
    instance.effective_public_key
  rescue ActiveRecord::StatementInvalid
    ENV["VAPID_PUBLIC_KEY"]
  end

  private

  def custom_public_key
    vapid_public_key
  end

  def custom_private_key
    vapid_private_key
  rescue ActiveRecord::Encryption::Errors::Base
    nil
  end
end
