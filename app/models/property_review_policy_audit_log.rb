class PropertyReviewPolicyAuditLog < ApplicationRecord
  belongs_to :tenant
  belongs_to :property_setting
  belongs_to :admin_user

  validates :version, numericality: { only_integer: true, greater_than: 0 }
  validates :changeset, :impact_snapshot, :policy_snapshot, presence: true
  validate :associations_share_tenant

  scope :recent, -> { order(created_at: :desc) }

  def readonly?
    persisted?
  end

  private

  def associations_share_tenant
    errors.add(:property_setting, "deve pertencer à mesma conta") if property_setting&.tenant_id != tenant_id
    errors.add(:admin_user, "deve pertencer à mesma conta") if admin_user&.tenant_id != tenant_id
  end
end
