class PortalListingState < ApplicationRecord
  belongs_to :habitation, optional: true
  belongs_to :portal_integration, primary_key: :portal, foreign_key: :portal, inverse_of: :portal_listing_states, optional: true

  validates :portal, presence: true, inclusion: { in: PortalIntegration::PORTALS }
  validates :last_event_type, presence: true
  validates :last_received_at, presence: true
end
