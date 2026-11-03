class ImovelwebLeadReceipt < ApplicationRecord
  belongs_to :imovelweb_connection
  belongs_to :lead, optional: true
  encrypts :payload
  validates :event_id, :received_at, presence: true
  validates :event_type, inclusion: { in: %w[CONTACTO CONTACTO_MENSAJE] }
  validates :status, inclusion: { in: %w[pending processed quarantined] }

  validate do
    if lead && imovelweb_connection && lead.tenant_id != imovelweb_connection.tenant_id
      errors.add(:lead, "deve pertencer à conta da conexão")
    end
  end

  def quarantine!(reason)
    update!(status: "quarantined", reason: reason, processed_at: Time.current)
  end
end
