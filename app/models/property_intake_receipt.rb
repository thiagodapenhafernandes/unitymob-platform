class PropertyIntakeReceipt < ApplicationRecord
  include TenantScoped

  belongs_to :habitation, optional: true

  def protocol
    format("PC-%06d", id)
  end
end
