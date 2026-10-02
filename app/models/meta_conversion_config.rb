class MetaConversionConfig < ApplicationRecord
  include TenantScoped

  validates :dataset_id, presence: true
  validates :tenant_id, uniqueness: true

  def self.instance(tenant:)
    for_tenant(tenant).first_or_initialize
  end

  # Envio usa o token da conexão Meta existente (login OAuth da conta), sem
  # segredo próprio: prefere integrações não expiradas. Expirado => pausa até
  # reconectar, igual à ingestão de leads.
  def sending_token
    UserMetaIntegration
      .owned_by_tenant(tenant_id)
      .where.not(access_token: [nil, ""])
      .order(Arel.sql("CASE WHEN token_expires_at IS NULL OR token_expires_at > NOW() THEN 0 ELSE 1 END"))
      .pick(:access_token)
  end

  def active?
    enabled? && dataset_id.present? && sending_token.present?
  end
end
