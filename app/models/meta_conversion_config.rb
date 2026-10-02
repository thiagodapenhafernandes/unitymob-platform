class MetaConversionConfig < ApplicationRecord
  include TenantScoped

  validates :tenant_id, uniqueness: true
  validate :datasets_must_have_selection

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

  def dataset_list
    Array(self[:datasets]).filter_map do |entry|
      id = entry["id"] || entry[:id]
      next if id.blank?

      { "id" => id.to_s, "name" => (entry["name"] || entry[:name]).to_s.presence || id.to_s }
    end.uniq { |entry| entry["id"] }
  end

  def active?
    enabled? && dataset_list.any? && sending_token.present?
  end

  private

  def datasets_must_have_selection
    errors.add(:datasets, :blank) if dataset_list.blank?
  end
end
