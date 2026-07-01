class LeadLabeling < ApplicationRecord
  include TenantScoped

  belongs_to :lead
  belongs_to :lead_label

  validates :lead_id, uniqueness: { scope: :lead_label_id }
end
