class AiPropertyShareAuditEvent < ApplicationRecord
  include TenantScoped
  belongs_to :ai_property_share_collection
  belongs_to :admin_user, optional: true
  belongs_to :lead, optional: true
  belongs_to :habitation, optional: true
  validates :event_type, presence: true
end
