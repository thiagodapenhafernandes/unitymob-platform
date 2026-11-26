class ChavesNaMaoLeadReceipt < ApplicationRecord
  belongs_to :chaves_na_mao_connection
  belongs_to :lead, optional: true
  encrypts :payload
  validates :payload_digest, :payload, :received_at, presence: true
  validates :event_id, presence: true, length: { maximum: 255 }, unless: -> { status == "captured" }
  validates :status, inclusion: { in: %w[captured pending processed quarantined] }
  validate do
    if lead && lead.tenant_id != chaves_na_mao_connection.tenant_id
      errors.add(:lead, "deve pertencer à conta da conexão")
    end
  end

  def quarantine!(reason)
    update!(status: "quarantined", reason: reason, processed_at: Time.current)
  end
end
