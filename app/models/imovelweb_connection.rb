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

  def receiving?
    encryption_ready? && ENV["IMOVELWEB_RECEIVING_ENABLED"] == "true" && enabled? && authorized_at.present? && tenant.active?
  end
end
