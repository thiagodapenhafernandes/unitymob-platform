class GoogleCalendarIntegrationSetting < ApplicationRecord
  include EncryptionAvailability

  DEFAULT_CALENDAR_ID = "fotografias.saluteimoveis@gmail.com".freeze
  DEFAULT_DURATION_MINUTES = 60
  MIN_DURATION_MINUTES = 15
  MAX_DURATION_MINUTES = 480

  belongs_to :tenant

  encrypts :service_account_json

  validates :tenant_id, uniqueness: true
  validates :default_duration_minutes,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: MIN_DURATION_MINUTES,
              less_than_or_equal_to: MAX_DURATION_MINUTES
            }
  validate :validate_required_fields_when_enabled
  validate :validate_service_account_json

  before_validation :normalize_values

  def self.for(tenant)
    raise ArgumentError, "Tenant obrigatório para configurar Google Calendar" if tenant.blank?

    where(tenant: tenant).first_or_initialize(
      calendar_id: DEFAULT_CALENDAR_ID,
      default_duration_minutes: DEFAULT_DURATION_MINUTES
    )
  end

  def configured?
    return false unless enabled?
    return false unless encryption_ready?

    calendar_id.present? && service_account_json.present?
  rescue ActiveRecord::Encryption::Errors::Base
    false
  end

  def service_account_configured?
    return false unless encryption_ready?

    service_account_json.present?
  rescue ActiveRecord::Encryption::Errors::Base
    false
  end

  def missing_configuration_items
    items = []
    items << "criptografia do servidor (AR_ENCRYPTION_*)" unless encryption_ready?
    items << "ID da agenda" if calendar_id.blank?
    items << "JSON da service account" unless service_account_configured?
    items
  end

  def service_account_credentials
    JSON.parse(service_account_json.to_s)
  end

  private

  def normalize_values
    self.calendar_id = calendar_id.to_s.strip.presence
    self.default_duration_minutes = default_duration_minutes.to_i if default_duration_minutes.present?
  end

  def validate_required_fields_when_enabled
    return unless enabled?

    errors.add(:base, "Configure as chaves AR_ENCRYPTION_* antes de salvar credenciais da agenda.") unless encryption_ready?
    errors.add(:calendar_id, "não pode ficar em branco") if calendar_id.blank?
    errors.add(:service_account_json, "não pode ficar em branco") unless service_account_configured?
  end

  def validate_service_account_json
    return if service_account_json.blank?

    credentials = JSON.parse(service_account_json.to_s)
    errors.add(:service_account_json, "precisa ser de uma service account") unless credentials["type"] == "service_account"
    errors.add(:service_account_json, "precisa conter client_email") if credentials["client_email"].blank?
    errors.add(:service_account_json, "precisa conter private_key") if credentials["private_key"].blank?
  rescue JSON::ParserError
    errors.add(:service_account_json, "precisa ser um JSON válido")
  rescue ActiveRecord::Encryption::Errors::Base
    errors.add(:service_account_json, "não pôde ser lido com as chaves de criptografia atuais")
  end
end
