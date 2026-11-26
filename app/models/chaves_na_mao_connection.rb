class ChavesNaMaoConnection < ApplicationRecord
  include TenantScoped
  include EncryptionAvailability

  encrypts :integration_token
  has_many :chaves_na_mao_lead_receipts, dependent: :restrict_with_error
  before_validation { self.route_key ||= SecureRandom.uuid }
  normalizes :account_code, :integration_token, with: ->(value) { value.strip.presence }
  normalizes :login_email, with: ->(value) { value.strip.downcase.presence }
  validates :login_email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }, if: :enabled?
  validates :tenant_id, uniqueness: true
  validates :route_key, presence: true, uniqueness: true
  validates :account_code, presence: true, format: { with: /\A[0-9]{1,32}\z/ }
  validates :integration_token, presence: true, length: { maximum: 1024 }, if: :enabled?
  validate do
    if persisted? && (%w[tenant_id route_key].any? { |field| will_save_change_to_attribute?(field) } ||
        (will_save_change_to_account_code? && !account_code_editable?))
      errors.add(:base, "A identidade da conexão não pode ser alterada.")
    end
    errors.add(:base, "A criptografia precisa estar disponível para receber eventos.") if enabled? && !encryption_ready?
  end

  def account_code_editable?
    !enabled_in_database && !chaves_na_mao_lead_receipts.exists?
  end

  def receiving?
    enabled? && login_email.present? && encryption_ready? && tenant.active?
  end

  def authenticated?(authorization)
    return false unless receiving?

    scheme, credentials = authorization.to_s.split(" ", 2)
    return false unless scheme&.casecmp?("Basic") && credentials.present? && integration_token.present? && login_email.present?

    email, token = Base64.strict_decode64(credentials).split(":", 2)
    email.present? && token.present? &&
      ActiveSupport::SecurityUtils.secure_compare(login_email, email.strip.downcase) &&
      ActiveSupport::SecurityUtils.secure_compare(integration_token, token)
  rescue ArgumentError
    false
  end
end
