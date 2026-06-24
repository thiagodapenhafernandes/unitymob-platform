class EmailSetting < ApplicationRecord
  include EncryptionAvailability

  encrypts :smtp_password

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

  # Singleton.
  def self.instance
    first_or_create!
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

  def from_address
    return from_email if from_name.blank?

    "#{from_name} <#{from_email}>"
  end

  # Hash compatível com ActionMailer `delivery_method_options` (:smtp).
  def smtp_settings
    {
      address:              smtp_address,
      port:                 smtp_port,
      domain:               smtp_domain.presence,
      user_name:            smtp_user_name,
      password:             smtp_password,
      authentication:       smtp_authentication.presence || "plain",
      enable_starttls_auto: smtp_enable_starttls_auto
    }.compact
  end
end
