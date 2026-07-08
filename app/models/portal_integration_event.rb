class PortalIntegrationEvent < ApplicationRecord
  # TenantScoped fornece belongs_to :tenant, o scope for_tenant e a inferência
  # de tenant. Incluído só quando a coluna existe (tolerante pré-migration).
  include TenantScoped if column_names.include?("tenant_id")

  belongs_to :habitation, optional: true
  belongs_to :portal_integration, primary_key: :portal, foreign_key: :portal, inverse_of: :portal_integration_events, optional: true

  validates :portal, presence: true, inclusion: { in: PortalIntegration::PORTALS }
  validates :event_type, presence: true
  validates :received_at, presence: true
end
