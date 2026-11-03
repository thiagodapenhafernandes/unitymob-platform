class ImovelwebListing < ApplicationRecord
  belongs_to :imovelweb_connection
  belongs_to :habitation
  validates :reference, presence: true, uniqueness: { scope: :imovelweb_connection_id }
  validates :external_id, uniqueness: { scope: :imovelweb_connection_id }, allow_nil: true
  validate do
    if habitation && imovelweb_connection && habitation.tenant_id != imovelweb_connection.tenant_id
      errors.add(:habitation, "deve pertencer à conta da conexão")
    end
  end
end
