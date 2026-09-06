class AccountMembership < ApplicationRecord
  validates :instance_id, :tenant_id, :user_id, :email, :tenant_name, :source_updated_at, presence: true
  validates :instance_id, :tenant_id, :user_id, length: { maximum: 100 }
  validates :email, length: { maximum: 254 }
  validates :tenant_name, length: { maximum: 200 }

  def public_account
    config = Gateway::Discovery.instance(instance_id)
    return unless config && config.fetch('tenant_ids', []).map(&:to_s).include?(tenant_id)
    { id: id, instance_id: instance_id, tenant_id: tenant_id, name: tenant_name,
      origin: Gateway::Discovery.origin(config.fetch('origin')) }
  end
end
