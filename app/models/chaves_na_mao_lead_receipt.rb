class ChavesNaMaoLeadReceipt < ApplicationRecord
  belongs_to :chaves_na_mao_connection
  encrypts :payload
  validates :payload_digest, :payload, :received_at, presence: true
end
