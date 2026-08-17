class LeadFavorite < ApplicationRecord
  include TenantScoped

  belongs_to :admin_user
  belongs_to :lead

  validates :lead_id, uniqueness: { scope: :admin_user_id }
  validate :associations_belong_to_same_tenant

  private

  def associations_belong_to_same_tenant
    {
      admin_user: admin_user,
      lead: lead
    }.each do |name, record|
      next if record.blank? || tenant.blank? || record.tenant_id == tenant_id

      errors.add(name, "deve pertencer à mesma conta do favorito")
    end
  end
end
