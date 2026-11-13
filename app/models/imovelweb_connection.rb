class ImovelwebConnection < ApplicationRecord
  include TenantScoped
  include EncryptionAvailability
  has_many :imovelweb_listings, dependent: :restrict_with_error
  has_many :imovelweb_lead_receipts, dependent: :restrict_with_error
  before_validation { self.route_key ||= SecureRandom.uuid }
  validates :route_key, :client_code, presence: true
  validates :route_key, uniqueness: true
  validates :client_code, uniqueness: { scope: :environment }
  validates :environment, inclusion: { in: %w[sandbox production] }

  validate do
    if persisted? && %w[tenant_id route_key client_code environment].any? { |field| will_save_change_to_attribute?(field) }
      errors.add(:base, "A identidade da conexão não pode ser alterada; prepare uma nova conexão.")
    end
  end

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
