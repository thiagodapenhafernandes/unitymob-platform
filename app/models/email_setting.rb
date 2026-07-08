class EmailSetting < ApplicationRecord
  include EncryptionAvailability

  encrypts :smtp_password

  # SMTP escopado por CONTA com fallback GLOBAL opt-in:
  # - tenant_id NULL  = linha global (config do Admin do Sistema).
  # - tenant_id X     = SMTP próprio da conta X.
  # belongs_to tolerante pré-migration (coluna criada pela frente migrations).
  belongs_to :tenant, optional: true if column_names.include?("tenant_id")

  AUTHENTICATIONS = %w[plain login cram_md5].freeze

  validates :smtp_port,
            numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 65_535 },
            allow_nil: true
  validates :from_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :reply_to,   format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :smtp_authentication, inclusion: { in: AUTHENTICATIONS }, allow_blank: true

  with_options if: :enabled? do
    validates :smtp_address, :smtp_user_name, :from_email, presence: true
  end

  # Config GLOBAL (tenant_id NULL). Pré-migration (sem coluna) cai no singleton
  # legado (first_or_create!) — mantém o comportamento atual.
  def self.global
    return first_or_create! unless column_names.include?("tenant_id")

    where(tenant_id: nil).first_or_create!
  end

  # Retrocompat: chamadas existentes usam .instance = config global.
  def self.instance
    global
  end

  # SMTP efetivo do tenant para TRANSPORTE de e-mail:
  # - config própria da conta, se configured?;
  # - senão (se a conta é opt-in E a global está configured?) a global;
  # - senão nil (canal indisponível).
  # O ALVO (destinatário) continua sendo resolvido fora daqui.
  def self.for(tenant)
    if column_names.include?("tenant_id") && tenant.present?
      own = where(tenant_id: tenant.id).first
      return own if own&.configured?
    end

    if tenant.respond_to?(:use_global_email_fallback?) && tenant&.use_global_email_fallback?
      candidate = global
      return candidate if candidate.configured?
    end

    nil
  end

  # Pronto para enviar e-mails de verdade (gate usado na regra de distribuição).
  def configured?
    return false unless encryption_ready?

    enabled? &&
      smtp_address.present? &&
      smtp_user_name.present? &&
      smtp_password.present? &&
      from_email.present?
  rescue ActiveRecord::Encryption::Errors::Base
    false
  end

  # O que ainda falta para o canal ficar pronto — alimenta o hint da tela
  # (antes o aviso era genérico e ninguém sabia o que preencher).
  def missing_configuration_items
    items = []
    items << "criptografia do servidor (AR_ENCRYPTION_*)" unless encryption_ready?
    items << "ativar o canal" unless enabled?
    items << "servidor SMTP" if smtp_address.blank?
    items << "usuário SMTP" if smtp_user_name.blank?
    items << "senha SMTP" if (smtp_password.blank? rescue true)
    items << "e-mail do remetente" if from_email.blank?
    items
  end

  def from_address
    return from_email if from_name.blank?

    "#{from_name} <#{from_email}>"
  end

  # Hash compatível com ActionMailer `delivery_method_options` (:smtp).
  # Domínio para HELO e Message-ID: campo explícito ou o domínio do remetente.
  # Sem isso o Net::SMTP apresenta o hostname da máquina (ex.: *.local) —
  # pontuação alta nos filtros de spam.
  def mail_domain
    smtp_domain.presence || from_email.to_s.split("@").last.presence
  end

  def smtp_settings
    {
      address:              smtp_address,
      port:                 smtp_port,
      domain:               mail_domain,
      user_name:            smtp_user_name,
      password:             smtp_password,
      authentication:       smtp_authentication.presence || "plain",
      enable_starttls_auto: smtp_enable_starttls_auto
    }.compact
  end
end
