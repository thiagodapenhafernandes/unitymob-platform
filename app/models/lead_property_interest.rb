class LeadPropertyInterest < ApplicationRecord
  include TenantScoped

  belongs_to :lead
  belongs_to :habitation

  validates :habitation_id, uniqueness: { scope: :lead_id }
  validate :habitation_belongs_to_tenant

  private

  # Mesma regra do Lead#property_id: o imóvel precisa ser do mesmo tenant.
  def habitation_belongs_to_tenant
    return if habitation.blank? || tenant.blank?
    return if habitation.tenant_id == tenant_id

    errors.add(:habitation, "deve pertencer ao mesmo Tenant")
  end
end
