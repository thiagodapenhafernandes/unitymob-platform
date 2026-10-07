class LinkedinLeadReceipt < ApplicationRecord
  include TenantScoped
  belongs_to :lead, optional: true
  validates :response_id, presence: true
end
