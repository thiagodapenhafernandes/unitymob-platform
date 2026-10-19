class Ga4ConversionConfig < ApplicationRecord
  include TenantScoped
  include EncryptionAvailability

  encrypts :api_secret
  encrypts :reporting_credentials

  validates :tenant_id, uniqueness: true
  validates :measurement_id, format: { with: /\AG-[A-Z0-9]+\z/ }, allow_blank: true
  validates :measurement_id, :api_secret, :activated_at, presence: true, if: :enabled?
  validates :reporting_property_id, format: { with: /\A[1-9]\d{0,19}\z/ }, allow_blank: true
  validates :reporting_property_id, :reporting_credentials, presence: true, if: :reporting_enabled?
  validate :validate_reporting_credentials

  def reporting_configured?
    reporting_enabled? && encryption_ready? && reporting_property_id.present? && reporting_credentials.present?
  rescue ActiveRecord::Encryption::Errors::Base
    false
  end

  def reporting_credentials_data
    JSON.parse(reporting_credentials).slice("type", "client_email", "private_key", "private_key_id", "project_id")
      .merge("token_uri" => "https://oauth2.googleapis.com/token")
  end

  def active?
    enabled? && encryption_ready? && measurement_id.present? && api_secret.present? && activated_at.present? && activated_at <= Time.current
  rescue ActiveRecord::Encryption::Errors::Base
    false
  end

  private

  def validate_reporting_credentials
    return if reporting_property_id.blank? && reporting_credentials.blank?

    errors.add(:reporting_property_id, "é obrigatório para leitura do GA4") if reporting_property_id.blank?
    unless reporting_credentials.present? && reporting_credentials.bytesize <= 65_536
      errors.add(:reporting_credentials, "informe o JSON da conta de serviço (até 64 KB)")
      return
    end

    data = JSON.parse(reporting_credentials)
    valid = data.is_a?(Hash) && data["type"] == "service_account" &&
      data["client_email"].to_s.match?(/\A[^@\s]+@[^@\s]+\.iam\.gserviceaccount\.com\z/) &&
      data["private_key"].present? &&
      (data["token_uri"].blank? || data["token_uri"] == "https://oauth2.googleapis.com/token")
    valid &&= OpenSSL::PKey.read(data["private_key"]).private?
    errors.add(:reporting_credentials, "informe uma conta de serviço válida do Google") unless valid
  rescue JSON::ParserError, OpenSSL::PKey::PKeyError, ArgumentError
    errors.add(:reporting_credentials, "informe uma conta de serviço válida do Google")
  end
end
