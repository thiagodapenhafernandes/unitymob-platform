class PortalIntegrationEvent < ApplicationRecord
  belongs_to :habitation, optional: true
  belongs_to :portal_integration, primary_key: :portal, foreign_key: :portal, inverse_of: :portal_integration_events, optional: true

  validates :portal, presence: true, inclusion: { in: PortalIntegration::PORTALS }
  validates :event_type, presence: true
  validates :received_at, presence: true
end
