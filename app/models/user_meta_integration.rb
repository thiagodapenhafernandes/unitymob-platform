class UserMetaIntegration < ApplicationRecord
  belongs_to :admin_user
  belongs_to :tenant, optional: true
  has_many :meta_facebook_pages, dependent: :destroy
  has_many :meta_lead_forms, through: :meta_facebook_pages

  # Modelo agência: uma integração por usuário POR CONTA. Guards has_attribute?
  # mantêm o código funcional antes da migration 20260705000001.
  before_validation { self.tenant_id ||= admin_user&.tenant_id if has_attribute?(:tenant_id) }
  validates :tenant_id, presence: true, if: -> { has_attribute?(:tenant_id) }

  validates :access_token, presence: true
  validates :facebook_user_id, presence: true

  # Tenant efetivo mesmo pré-migration.
  def owner_tenant_id
    (tenant_id if has_attribute?(:tenant_id)) || admin_user&.tenant_id
  end

  def expired?
    token_expires_at.present? && token_expires_at < Time.current
  end
end
