class PortalListingState < ApplicationRecord
  # TenantScoped fornece belongs_to :tenant, o scope for_tenant e a inferência
  # de tenant. Incluído só quando a coluna existe (tolerante pré-migration).
  include TenantScoped if column_names.include?("tenant_id")

  belongs_to :habitation, optional: true
  belongs_to :portal_integration, primary_key: :portal, foreign_key: :portal, inverse_of: :portal_listing_states, optional: true

  validates :portal, presence: true, inclusion: { in: PortalIntegration::PORTALS }
  validates :last_event_type, presence: true
  validates :last_received_at, presence: true

  # Tenant é inferível a partir da habitation (única associação com tenant aqui);
  # TenantScoped#inferred_tenant já cobre :habitation.
end
