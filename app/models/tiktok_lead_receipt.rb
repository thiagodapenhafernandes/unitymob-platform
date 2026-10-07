class TiktokLeadReceipt < ApplicationRecord
  include TenantScoped
  belongs_to :lead, optional: true
  validates :advertiser_id, :external_id, presence: true
end
