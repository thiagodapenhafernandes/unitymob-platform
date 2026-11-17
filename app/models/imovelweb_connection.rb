class ImovelwebConnection < ApplicationRecord
  include TenantScoped
  include EncryptionAvailability
  encrypts :binding_challenge_token, :binding_proof
  has_many :imovelweb_listings, dependent: :restrict_with_error
  has_many :imovelweb_lead_receipts, dependent: :restrict_with_error
  before_validation { self.route_key ||= SecureRandom.uuid }
  validates :route_key, :client_code, presence: true
  validates :route_key, uniqueness: true
  validates :client_code, uniqueness: { scope: :environment }
  validates :environment, inclusion: { in: %w[sandbox production] }

  validate do
    if persisted? && %w[tenant_id route_key environment].any? { |field| will_save_change_to_attribute?(field) }
      errors.add(:base, "A identidade da conexão não pode ser alterada; prepare uma nova conexão.")
    end
  end

  validate do
    if persisted? && will_save_change_to_client_code?
      safe_draft = binding_editable? && client_code_in_database.to_s.match?(/\A(?:um|pending)-[0-9a-f-]{36}\z/) &&
        client_code == advertiser_code && !imovelweb_lead_receipts.exists? && !imovelweb_listings.exists?
      errors.add(:base, "A identidade da conexão confirmada não pode ser alterada.") unless safe_draft
    end
  end

  validates :advertiser_code, format: { with: /\A[0-9]{1,32}\z/, message: "deve ser o código numérico da sucursal" }, on: :binding_request

  normalizes :advertiser_code, with: ->(value) { value.strip.presence }
  validates :advertiser_code, length: { maximum: 128 }, format: { with: /\A[A-Za-z0-9_.-]+\z/ }, allow_blank: true
  validates :advertiser_code, uniqueness: { scope: [:tenant_id, :environment] }, allow_blank: true
  validates :advertiser_code, presence: true, on: :binding_request

  def binding_editable?
    environment == "production" && !enabled? && authorized_at.blank?
  end

  def receiving?
    encryption_ready? && ENV["IMOVELWEB_RECEIVING_ENABLED"] == "true" && enabled? && authorized_at.present? && tenant.active?
  end
end
